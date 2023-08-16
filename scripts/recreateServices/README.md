# Recreate EKS Services As Internal Load Balancers

1. [Merge this PR to target environment](https://github.com/cds-snc/notification-terraform/pull/883)
    This PR does the following:
    - Creates new secondary target groups
    - Modifies existing aws_lb_listener_rules to use both the old and new target groups

2. Note the values of the new target group ARNs in the output. Example:
    ```
    secondary_admin_target_group_arn = "arn:aws:elasticloadbalancing:ca-central-1:419291849580:targetgroup/admin-secondary/691172d10f3c0cdb"
    secondary_api_target_group_arn = "arn:aws:elasticloadbalancing:ca-central-1:419291849580:targetgroup/k8s-api-secondary/395aceaf447e2195"
    secondary_document_api_target_group_arn = "arn:aws:elasticloadbalancing:ca-central-1:419291849580:targetgroup/doc-api-secondary/a0148924f7793d82"
    secondary_document_target_group_arn = "arn:aws:elasticloadbalancing:ca-central-1:419291849580:targetgroup/doc-api-secondary/a0148924f7793d82"
    secondary_documentation_target_group_arn = "arn:aws:elasticloadbalancing:ca-central-1:419291849580:targetgroup/document-secondary/8c99c95c9ac65667"
    ```

3. Modify the targetGroups.yaml in the appropriate environment folder in ./scripts/recreateServices/secondaryServices
    - Copy/paste the target group ARNs from step 2 into the appropriate sections

4. From the scripts/recreateServices directory, run ./createSecondaryServices.sh <env> where <env> is the target environment
5. Verify that the secondary services are created
6. In the AWS console, verify there are targets in the new target groups
7. From the scripts/recreateServices directory, run ./recreateServices.sh <env> where <env> is the target environment
8. Verify that the old services are recreated as internal load balancers
9. In AWS console, verify the old target groups still have targets
10. From the scripts/recreateServices directory, run ./deleteServices.sh <env> where <env> is the target environment 
11. Revert notification-terraform PR