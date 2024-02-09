# Notify Helmfile Usage
## Pre-Requisites
Install helm and helmfile, and configure your kubernetes contexts using setup.sh
```bash
./setup.sh
```

**Note: setup.sh assumes you have not changed the context names from their original format. If you have done this already, please either modify setup.sh to rename them as appropriate, or remove your contexts and add them back with their default name.**

## Overview
Helmfile is an abstraction layer on top of helm in much the same way that terragrunt is an abstraction layer on top of terraform. It allows developers to manage multiple applications across multiple environments using a single code source.

Helmfile is currently being used in a pilot test to manage the internal utilities and applications used by Notify Developers. **It is not being used to manage Notify applications directly.**

The following utilities are part of this project:
- Nginx Ingress Controller - Used to control the ingress and egress of utilities under EKS such as Hasura
- Kubernetes Secrets CSI Driver - a system component required for AWS Secrets Provider
- AWS Secrets Provider - a utility that allows Kubernetes to inject values from the AWS Secrets Manager directly into pods

## Usage

### Notify Specific

Before running helmfile locally, you must first populate the required environment variables by running the getContext.sh

1. Ensure you are logged into the appropriate AWS Account
2. Populate environment variables using 
  ```bash
  source getContext.sh
  ```

### Sub-Commands

Helmfile has many commands available. Please see the [helmfile documentation](https://helmfile.readthedocs.io/en/latest/) for a full list. In this document we will cover the three main commands used day-to-day.

#### Diff

Diff will provide an output showing how an apply would change the environment. It is similar in concept to terraform/terragrunt plan. It is recommended to always run a diff before running an apply so that you can be sure of what helmfile will do.

#### Apply

Apply will do as it says - apply any changes it detects between the helm state and the local state. It is always recommended to do a diff before applying.

#### Destroy

Destroy will delete the targeted releases, and (usually) all of their components.

*Note: helmfile will not delete namespaces*

## Concepts

### Environments

Helmfile lets developers declaritively create environments and create logic based on those environments. For example, it is possible to assign different values to a deployment based on which environment it is in: 

```go
      {{ if eq .Environment.Name "dev"}} 
        value: devValue
      {{ else if eq .Environment.Name "staging" }}
        value: stagingValue
      {{ else }}
        value: defaultValue
      {{ end }}
```

The environment name should be passed when running helmfile:

```bash
helmfile --environment someEnvironment apply
```

### Labels

Helmfile allows the creation of labels attached to each release which can then be used to filter or target the helmfile exectution.

Example:

```bash
helmfile --environment dev --selector label1Name=label1Value,label2Name=label2Value apply
```

These labels and values are arbitrary. A common set of labels may be something like:
- app
- tier
- category

Using this methodology it is possible to target specific parts of the environment, and can be used to get around the limitations of Kubernetes and dependencies. 

#### Example

Let's say that you have a three tiered application that has a front end, middle tier, and database. For the front end to work, the database and middle tier need to be up and running first. 

```yaml
  - name: frontend
    namespace: example
    labels:
      app: myapp
      tier: frontend
      category: deliverables
    chart: charts/myapp-frontend

  - name: middle-tier
    namespace: example
    labels:
      app: myapp
      tier: middle
      category: deliverables
    chart: charts/myapp-middle

  - name: database
    namespace: example
    labels:
      app: myapp
      tier: database
      category: deliverables
    chart: charts/mydatabase
```

If you did a straight helmfile apply, all three would be released at once, and while Kubernetes would eventually sort it out, it would not be as clean. 

Instead we could run targeted helmfiles using label selectors.

```bash
helmfile --environment production --selector app=myapp,tier=database apply

helmfile --environment production --selector app=myapp,tier=middle apply

helmfile --environment production --selector app=myapp,tier=frontend apply
```

By doing the above, we could apply each section individually, wait for them to normalize, and then proceed to the next.

The same philosophy could apply to other scenarios. For example, if there are several kubernetes system level components that must be installed in a new environment (csi drivers, ebs drivers, etc), you could label all of those releases with the category system and then have them all installed at once:

```bash 
helmfile --environment production --selector category=system apply 
```


