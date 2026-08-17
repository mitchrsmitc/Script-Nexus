# Mitchell.dev Script Nexus v2

Purple GitHub-backed script library for GitHub Pages.

## Configure

Edit `CONFIG` at the top of `scripts.js` and set `owner`, `repo`, and `branch`.

## Publishing from the site

Create a fine-grained GitHub personal access token limited to this repository with **Contents: Read and write**. Open **Add script**, provide metadata, choose a file, and publish. The token is held only in page memory and is not written to local storage. Close the tab after publishing.

For stronger security and multi-user use, replace the browser token flow with a GitHub App and a small backend. Never place a permanent token in source code.

## Data model

- Full scripts: `scripts/<category>/<filename>`
- Search index: `scripts/manifest.json`

Do not upload passwords, keys, tokens, confidential configurations, private inventories, or employer/customer data.
