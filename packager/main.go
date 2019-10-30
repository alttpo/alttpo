package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
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

func main() {
	// grab the Bearer token for cirrus-ci API from env var:
	cirrusToken := os.Getenv("CIRRUS_CI_TOKEN")

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
			"owner": "JamesDunne",
			"name":  "bsnes-angelscript",
		},
	}
	buf := &bytes.Buffer{}
	enc := json.NewEncoder(buf)
	err := enc.Encode(gqlQuery)
	if err != nil {
		log.Fatal(err)
	}

	// build POST request with Authorization header:
	req, err := http.NewRequest("POST", "https://api.cirrus-ci.com/graphql", buf)
	if err != nil {
		log.Fatal(err)
	}
	req.Header.Add("Authorization", "Bearer "+cirrusToken)
	req.Header.Add("Content-Type", "application/json")

	// execute POST request:
	rsp, err := http.DefaultClient.Do(req)
	if err != nil {
		log.Fatal(err)
	}

	// decode JSON response:
	gqlResponse := &GQLResponse{}
	dec := json.NewDecoder(rsp.Body)
	err = dec.Decode(gqlResponse)
	if err != nil {
		log.Fatal(err)
	}

	for _, t := range gqlResponse.Data.GithubRepository.LastDefaultBranchBuild.LatestGroupTasks {
		fmt.Printf("%s: %s %s\n", t.Id, t.Name, t.Status)
	}
}
