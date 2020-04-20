package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/pierrre/archivefile/zip"
)

type GQLQuery struct {
	Query     string                 `json:"query"`
	Variables map[string]interface{} `json:"variables"`
}
type Build struct {
	Edges []struct {
		Node struct {
			Id               string `json:"id"`
			Status           string `json:"status"`
			Branch           string `json:"branch"`
			Hash             string `json:"changeIdInRepo"`
			LatestGroupTasks []struct {
				Id     string `json:"id"`
				Name   string `json:"name"`
				Status string `json:"status"`
			} `json:"latestGroupTasks"`
		} `json:"node"`
	} `json:"edges"`
}
type GQLResponse struct {
	Data struct {
		GithubRepository struct {
			BranchBuild *Build `json:"branchBuild"`
			MasterBuild *Build `json:"masterBuild"`
		} `json:"githubRepository"`
	} `json:"data"`
}

func fetchBuildArtifacts(owner, repository, branch string) (gqlResponse *GQLResponse, err error) {
	// build graphQL query POST body:
	// gqlQuery := GQLQuery{
	//   Query: `query GitHubRepositoryQuery($owner: String!, $name: String!) {
	//   githubRepository(owner: $owner, name: $name) {
	//     lastDefaultBranchBuild {
	//       latestGroupTasks { id name status }
	//     }
	//   }
	// }`,
	//   Variables: map[string]interface{}{
	//     "owner": owner,
	//     "name":  repository,
	//   },
	// }
	var gqlQuery GQLQuery
	if branch != "master" {
		gqlQuery = GQLQuery{
			Query: `query GitHubRepositoryQuery($owner: String!, $name: String!, $branch: String!) {
  githubRepository(owner: $owner, name: $name) {
    branchBuild: builds(last: 1, branch: $branch) {
      edges {
        node {
          id
          status
          branch
          changeIdInRepo
          latestGroupTasks {
            id
            name
            status
          }
        }
      }
    }
    masterBuild: builds(last: 1, branch: "master") {
      edges {
        node {
          id
          status
          branch
          changeIdInRepo
          latestGroupTasks {
            id
            name
            status
          }
        }
      }
    }
  }
}`,
			Variables: map[string]interface{}{
				"owner":  owner,
				"name":   repository,
				"branch": branch,
			},
		}
	} else {
		// master-only branch:
		gqlQuery = GQLQuery{
			Query: `query GitHubRepositoryQuery($owner: String!, $name: String!) {
  githubRepository(owner: $owner, name: $name) {
    masterBuild: builds(last: 1, branch: "master") {
      edges {
        node {
          id
          status
          branch
          changeIdInRepo
          latestGroupTasks {
            id
            name
            status
          }
        }
      }
    }
  }
}`,
			Variables: map[string]interface{}{
				"owner": owner,
				"name":  repository,
			},
		}
	}

	buf := &bytes.Buffer{}
	enc := json.NewEncoder(buf)
	err = enc.Encode(gqlQuery)
	if err != nil {
		return
	}
	// build POST request with Authorization header:
	req, err := http.NewRequest("POST", "https://api.cirrus-ci.com/graphql", buf)
	if err != nil {
		return
	}

	//req.Header.Add("Authorization", "Bearer "+cirrusToken)
	req.Header.Add("Content-Type", "application/json")
	// execute POST request:
	rsp, err := http.DefaultClient.Do(req)
	if err != nil {
		return
	}

	// decode JSON response:
	gqlResponse = &GQLResponse{}
	dec := json.NewDecoder(rsp.Body)
	err = dec.Decode(gqlResponse)
	if err != nil {
		return
	}

	return
}

type Arch struct {
	Name            string
	BsnesArtifactId string
	Hash            string
}

func downloadAndExtractZip(url string, dir string) (err error) {
	// get ZIP file:
	log.Printf("GET %s\n", url)
	rsp, err := http.Get(url)
	if err != nil {
		return
	}

	// download straight into memory here (maybe want to redirect to a tmp file):
	zipBytes, err := ioutil.ReadAll(rsp.Body)
	if err != nil {
		return
	}

	// extract ZIP contents from memory out to local files in `dir`:
	err = extractZip(zipBytes, dir)
	if err != nil {
		return
	}

	return
}

func extractZip(zipBytes []byte, dir string) (err error) {
	log.Printf("extracting to '%s'\n", dir)

	err = zip.Unarchive(bytes.NewReader(zipBytes), int64(len(zipBytes)), dir, func(archivePath string) {
		log.Printf("extracting '%s'\n", archivePath)
	})

	return
}

func zipDirectory(zipName string, dir string) (err error) {
	var w *os.File
	w, err = os.Create(zipName)
	if err != nil {
		return
	}
	defer w.Close()
	err = zip.Archive(dir, w, func(archivePath string) {
		log.Printf("archiving '%s'\n", archivePath)
	})
	log.Printf("archived to '%s'\n", zipName)
	return
}

func main() {
	var err error

	// grab env vars:
	waitStr := os.Getenv("PACKAGER_WAIT_FOR_BUILD")
	// if strconv cannot parse, will default to false. ignore the error.
	waitForBuild, _ := strconv.ParseBool(waitStr)

	targetArch := os.Getenv("PACKAGER_TARGET_ARCH")
	fmt.Printf("PACKAGER_TARGET_ARCH=%s\n", targetArch)

	branch := os.Getenv("CIRRUS_BRANCH")
	fmt.Printf("CIRRUS_BRANCH=%s\n", branch)

	hash := os.Getenv("CIRRUS_CHANGE_IN_REPO")
	fmt.Printf("CIRRUS_CHANGE_IN_REPO=%s\n", hash)

	if branch == "" {
		branch = "master"
	}
	fmt.Printf("branch=%v\n", branch)

	archs := make(map[string]*Arch)

	// BSNES emulator customized with AngelScript integration
	buildFound := false
retryLoop:
	for !buildFound {
		log.Printf("query latest builds for github.com/JamesDunne/bsnes-angelscript\n")
		bsnesArtifactIds, err := fetchBuildArtifacts("JamesDunne", "bsnes-angelscript", branch)
		if err != nil {
			log.Fatal(err)
		}

		// look at branch build first and fall back to master:
		for _, build := range []*Build{bsnesArtifactIds.Data.GithubRepository.BranchBuild, bsnesArtifactIds.Data.GithubRepository.MasterBuild} {
			if build == nil {
				continue
			}

			buildEdges := build.Edges
			if len(buildEdges) == 0 {
				log.Printf("no build found for branch '%s'", branch)
				continue
			}
			buildNode := buildEdges[0].Node
			log.Printf("build %s for branch '%s' %s is in status '%s'", buildNode.Id, buildNode.Branch, buildNode.Hash, buildNode.Status)
			if buildNode.Status != "COMPLETED" {
				// want to retry later:
				log.Printf("waiting 15 seconds to retry until COMPLETED\n")
				if waitForBuild {
					time.Sleep(time.Second * 15)
					break
				} else {
					break retryLoop
				}
			}

			for _, t := range buildNode.LatestGroupTasks {
				//log.Printf("bsnes %s: %s\n", t.Name, t.Id)
				arch, ok := archs[t.Name]
				if !ok {
					arch = &Arch{}
					archs[t.Name] = arch
				}
				arch.Name = t.Name
				arch.BsnesArtifactId = t.Id
				arch.Hash = buildNode.Hash
			}

			buildFound = true
			break
		}
	}

	// look up target arch to extract:
	arch, ok := archs[targetArch]
	if !ok {
		log.Printf("could not find requested PACKAGER_TARGET_ARCH='%s'; available archs are:\n", targetArch)
		for archName := range archs {
			log.Printf("  %s\n", archName)
		}
		os.Exit(1)
	}

	// packaging:
	nightly := fmt.Sprintf("alttp-multiplayer-%s-%s", hash[:7], arch.Hash[:7])
	os.RemoveAll(nightly)

	// download artifact ZIP and extract:
	bsnesZipUrl := fmt.Sprintf("https://api.cirrus-ci.com/v1/artifact/task/%s/bsnes-angelscript-nightly.zip", arch.BsnesArtifactId)
	err = downloadAndExtractZip(bsnesZipUrl, ".")
	if err != nil {
		log.Fatal(err)
	}

	// Rename extracted folder to new nightly folder:
	err = os.Rename("bsnes-angelscript-nightly", nightly)
	if err != nil {
		log.Println(err)
	}

	//  - mkdir -p alttp-multiplayer-nightly/test-scripts
	os.MkdirAll(nightly+"/test-scripts", os.ModeDir|os.FileMode(0755))

	//  - mv alttp-multiplayer-nightly/*.as alttp-multiplayer-nightly/test-scripts
	files, err := filepath.Glob(nightly + "/*.as")
	for _, p := range files {
		newPath := nightly + "/test-scripts/" + p[len(nightly+"/"):]
		os.Rename(p, newPath)
	}

	//  - cp -a angelscript/*.as alttp-multiplayer-nightly/test-scripts
	files, err = filepath.Glob("angelscript/*.as")
	for _, p := range files {
		newPath := nightly + "/test-scripts/" + p[len("angelscript/"):]
		os.Link(p, newPath)
	}

	//  - mv alttp-multiplayer-nightly/test-scripts/alttp-script.as alttp-multiplayer-nightly/alttp-script.as
	os.Rename(nightly+"/test-scripts/alttp-script.as", nightly+"/alttp-script.as")

	//  - cp -a README.md alttp-multiplayer-nightly
	os.Link("README.md", nightly+"/README.md")

	//  - cp -a join-a-game.png alttp-multiplayer-nightly
	os.Link("join-a-game.png", nightly+"/join-a-game.png")

	// archive nightly folder to a zip (leaving trailing slash off folder makes that the root):
	err = zipDirectory(nightly+".zip", nightly)
	if err != nil {
		log.Fatal(err)
	}
}
