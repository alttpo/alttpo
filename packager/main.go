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
	"strings"
)

type GQLQuery struct {
	Query     string                 `json:"query"`
	Variables map[string]interface{} `json:"variables"`
}
type GQLResponse struct {
	Data struct {
		GithubRepository struct {
			LastDefaultBranchBuild struct {
				LatestGroupTasks []struct {
					Id     string `json:"id"`
					Name   string `json:"name"`
					Status string `json:"status"`
				} `json:"latestGroupTasks"`
			} `json:"lastDefaultBranchBuild"`
		} `json:"githubRepository"`
	} `json:"data"`
}

func fetchBuildArtifacts(owner, repository string) (gqlResponse *GQLResponse, err error) {
	// build graphQL query POST body:
	//query := `{"query":"query GitHubRepositoryQuery($owner: String!, $name: String!) { githubRepository(owner: $owner, name: $name) { lastDefaultBranchBuild { latestGroupTasks { id name status } } } }","variables":{"owner":"JamesDunne","name":"bsnes-angelscript"}}`
	gqlQuery := GQLQuery{
		Query: `query GitHubRepositoryQuery($owner: String!, $name: String!) {
	  githubRepository(owner: $owner, name: $name) {
	    lastDefaultBranchBuild {
	      latestGroupTasks { id name status }
	    }
	  }
	}`,
		Variables: map[string]interface{}{
			"owner": owner,
			"name":  repository,
		},
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
	BassArtifactId  string
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
	outputDir := os.Getenv("PACKAGER_OUTPUT_DIR")
	targetArch := os.Getenv("PACKAGER_TARGET_ARCH")

	if outputDir == "" {
		// create a temporary directory to store artifacts:
		outputDir, err = ioutil.TempDir("", "alttp-build")
		if err != nil {
			log.Fatal(err)
		}
	}

	fmt.Printf("PACKAGER_OUTPUT_DIR=%s\n", outputDir)
	fmt.Printf("PACKAGER_TARGET_ARCH=%s\n", targetArch)

	archs := make(map[string]*Arch)

	// BSNES emulator customized with AngelScript integration
	log.Print("query latest build for github.com/JamesDunne/bsnes-angelscript\n")
	bsnesArtifactIds, err := fetchBuildArtifacts("JamesDunne", "bsnes-angelscript")
	if err != nil {
		log.Fatal(err)
	}

	for _, t := range bsnesArtifactIds.Data.GithubRepository.LastDefaultBranchBuild.LatestGroupTasks {
		//log.Printf("bsnes %s: %s\n", t.Name, t.Id)
		arch, ok := archs[t.Name]
		if !ok {
			arch = &Arch{}
			archs[t.Name] = arch
		}
		arch.Name = t.Name
		arch.BsnesArtifactId = t.Id
	}

	// SNES assembler
	log.Print("query latest build for github.com/JamesDunne/bass\n")
	bassArtifactIds, err := fetchBuildArtifacts("JamesDunne", "bass")
	if err != nil {
		log.Fatal(err)
	}

	for _, t := range bassArtifactIds.Data.GithubRepository.LastDefaultBranchBuild.LatestGroupTasks {
		//log.Printf("bass  %s: %s %s\n", t.Name, t.Id, t.Status)
		arch, ok := archs[t.Name]
		if !ok {
			arch = &Arch{}
			archs[t.Name] = arch
		}
		arch.Name = t.Name
		arch.BassArtifactId = t.Id
	}

	// look up target arch to extract:
	arch, ok := archs[targetArch]
	if !ok {
		log.Print("could not find requested PACKAGER_TARGET_ARCH; available archs are:\n")
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

	// download artifact ZIP and extract:
	bassZipUrl := fmt.Sprintf("https://api.cirrus-ci.com/v1/artifact/task/%s/bass-nightly.zip", arch.BassArtifactId)
	err = downloadAndExtractZip(bassZipUrl, outputDir, func(path string) string {
		// remove bass-nightly/ prefix from ZIP filenames:
		if strings.HasPrefix(path, "bass-nightly/") {
			return path[len("bass-nightly/"):]
		}
		return path
	})
	if err != nil {
		log.Fatal(err)
	}
}
