# Environment variable creation script
This script is meant as a helper to create environment variables for helmfile and help reduce the tedium of doing so.

It handles 4 scenarios as laid out [in the docs](https://docs.google.com/document/d/1kAXGzuKlmKiVJgp9-t19LcUo-pZ2Bu93gzEFYMFKjvk/edit?usp=sharing):
1. Scenario 1: same value across all environments
1. Scenario 2: environment-specific values
1. Scenario 3: variable based on environment name
1. Scenario 4: variables based on context variables

## Usage

### Install dependencies
`npm install`

### Run the script
`npm run add-env`

The script will prompt you for the variable name and lead you through the various scenarios.  Once complete, check that the updates are as you expect and create a PR!

