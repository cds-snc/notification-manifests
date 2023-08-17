# Recreate EKS Services As Internal Load Balancers


## Staging

1. [Merge this PR to target environment](https://github.com/cds-snc/notification-terraform/pull/887)
    This PR does the following:
    - Creates new secondary target groups
    
2. Note the values of the new target group ARNs in the output. Example:
    ```
    admin_secondary = "arn:aws:elasticloadbalancing:ca-central-1:419291849580:targetgroup/admin-secondary/691172d10f3c0cdb"
    api_secondary = "arn:aws:elasticloadbalancing:ca-central-1:419291849580:targetgroup/k8s-api-secondary/395aceaf447e2195"
    doc_api_secondary = "arn:aws:elasticloadbalancing:ca-central-1:419291849580:targetgroup/doc-api-secondary/a0148924f7793d82"
    document_secondary = "arn:aws:elasticloadbalancing:ca-central-1:419291849580:targetgroup/doc-api-secondary/a0148924f7793d82"
    ```

3. Modify the targetGroups.yaml in the appropriate environment folder in ./scripts/recreateServices/secondaryServices
    - Copy/paste the target group ARNs from step 2 into the appropriate sections

4. From the scripts/recreateServices directory, run ./createSecondaryServices.sh \<env\> where \<env\> is the target environment
5. Verify that the secondary services are created
6. In the AWS console, verify there are targets in the new target groups
7. [Merge this PR to target environment](https://github.com/cds-snc/notification-terraform/pull/889)
    This PR does the following:
    - Modifies existing aws_lb_listener_rules to use only the new target groups
8. Verify that the services are still working
9. Merge the manifests PR
8. From the scripts/recreateServices directory, run ./recreateServices.sh \<env\> where \<env\> is the target environment
9. Verify that the old services are recreated as internal load balancers
10. In AWS console, verify the old target groups still have targets
10. [Revert this PR to target environment](https://github.com/cds-snc/notification-terraform/pull/889)



## Production

1. Do a terraform release to production. The secondary target group PR is still in staging, so they will be created in prod now.
    
2. Note the values of the new target group ARNs in the output. Example:
    ```
    admin_secondary = "arn:aws:elasticloadbalancing:ca-central-1:419291849580:targetgroup/admin-secondary/691172d10f3c0cdb"
    api_secondary = "arn:aws:elasticloadbalancing:ca-central-1:419291849580:targetgroup/k8s-api-secondary/395aceaf447e2195"
    doc_api_secondary = "arn:aws:elasticloadbalancing:ca-central-1:419291849580:targetgroup/doc-api-secondary/a0148924f7793d82"
    document_secondary = "arn:aws:elasticloadbalancing:ca-central-1:419291849580:targetgroup/doc-api-secondary/a0148924f7793d82"
    ```

3. Modify the targetGroups.yaml in the appropriate environment folder in ./scripts/recreateServices/secondaryServices
    - Copy/paste the target group ARNs from step 2 into the appropriate sections

4. From the scripts/recreateServices directory, run ./createSecondaryServices.sh \<env\> where \<env\> is the target environment
5. Verify that the secondary services are created
6. In the AWS console, verify there are targets in the new target groups
7. [Merge this PR to target staging](https://github.com/cds-snc/notification-terraform/pull/889)
    This PR does the following:
    - Modifies existing aws_lb_listener_rules to use only the new target groups
8. Verify that the services are still working
9. Do a manifests release to production
8. From the scripts/recreateServices directory, run ./recreateServices.sh \<env\> where \<env\> is prod
9. Verify that the old services are recreated as internal load balancers
10. In AWS console, verify the old target groups still have targets
10. [Revert this PR to prod](https://github.com/cds-snc/notification-terraform/pull/889)
10. [Revert this PR to target prod](https://github.com/cds-snc/notification-terraform/pull/887) Maybe we don't do this for staging
11. From the scripts/recreateServices directory, run ./deleteServices.sh \<env\> where \<env\> is the target environment 
11. From the scripts/recreateServices directory, run ./deleteServices.sh <env\> where \<env\> is the target environment in prod
