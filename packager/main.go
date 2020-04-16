package main

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type GQLQuery struct {
	Query     string                 `json:"query"`
	Variables map[string]interface{} `json:"variables"`
}
type Build struct {
	Edges []struct {
		Node struct {
			Id string `json:"id"`
			Status string `json:"status"`
			Branch string `json:"branch"`
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
}

func downloadAndExtractZip(url string, dir string, rename func(path string) string) (err error) {
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
	err = extractZip(zipBytes, dir, rename)
	if err != nil {
		return
	}

	return
}

func extractZip(zipBytes []byte, dir string, rename func(path string) string) (err error) {
	log.Printf("extracting to '%s'\n", dir)

	zr, err := zip.NewReader(bytes.NewReader(zipBytes), int64(len(zipBytes)))
	if err != nil {
		return
	}

	// extract files:
	for _, f := range zr.File {
		fpath := rename(f.Name)

		log.Printf("extracting '%s'\n", fpath)

		err = func() error {
			fdir := filepath.Join(dir, filepath.Dir(fpath))
			os.MkdirAll(fdir, 0700)

			r, err := f.Open()
			if err != nil {
				return err
			}
			defer r.Close()

			path := filepath.Join(dir, fpath)
			of, err := os.OpenFile(path, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, f.Mode())
			if err != nil {
				return err
			}

			_, err = io.Copy(of, r)
			if err != nil {
				of.Close()
				return err
			}
			of.Close()

			err = os.Chtimes(path, f.Modified, f.Modified)
			if err != nil {
				log.Printf("WARN: chtimes: %v\n", err)
			}

			// TODO apply `f.Mode().Perm()`

			return nil
		}()
		if err != nil {
			return
		}
	}

	return
}

func main() {
	var err error

	// grab env vars:
	waitStr := os.Getenv("PACKAGER_WAIT_FOR_BUILD")
	// if strconv cannot parse, will default to false. ignore the error.
	waitForBuild, _ := strconv.ParseBool(waitStr)

	outputDir := os.Getenv("PACKAGER_OUTPUT_DIR")
	fmt.Printf("PACKAGER_OUTPUT_DIR=%s\n", outputDir)

	targetArch := os.Getenv("PACKAGER_TARGET_ARCH")
	fmt.Printf("PACKAGER_TARGET_ARCH=%s\n", targetArch)

	branch := os.Getenv("CIRRUS_BRANCH")
	fmt.Printf("CIRRUS_BRANCH=%s\n", branch)

	if outputDir == "" {
		// create a temporary directory to store artifacts:
		outputDir, err = ioutil.TempDir("", "alttp-build")
		if err != nil {
			log.Fatal(err)
		}
	}

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
			if buildNode.Status != "COMPLETED" {
				log.Printf("build %s for branch '%s' is in status '%s'", buildNode.Id, buildNode.Branch, buildNode.Status)
				// want to retry later:
				log.Printf("waiting 1 minute to retry until COMPLETED\n")
				if waitForBuild {
					time.Sleep(time.Minute)
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

	// download artifact ZIP and extract:
	bsnesZipUrl := fmt.Sprintf("https://api.cirrus-ci.com/v1/artifact/task/%s/bsnes-angelscript-nightly.zip", arch.BsnesArtifactId)
	err = downloadAndExtractZip(bsnesZipUrl, outputDir, func(path string) string {
		// remove bsnes-angelscript-nightly/ prefix from ZIP filenames:
		if strings.HasPrefix(path, "bsnes-angelscript-nightly/") {
			return path[len("bsnes-angelscript-nightly/"):]
		}
		return path
	})
	if err != nil {
		log.Fatal(err)
	}
}
