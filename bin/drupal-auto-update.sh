#!/bin/bash

UPDATES_APPLIED=false

# login to Terminus
echo -e "\nLogging into Terminus..."
terminus auth:login --machine-token=${TERMINUS_MACHINE_TOKEN}

# delete the multidev environment
echo -e "\nDeleting the ${TERMINUS_ENV} multidev environment..."
terminus multidev:delete $SITE_UUID.$TERMINUS_ENV --delete-branch --yes

# recreate the multidev environment
echo -e "\nRe-creating the ${TERMINUS_ENV} multidev environment..."
terminus multidev:create $SITE_UUID.live $TERMINUS_ENV

# check for upstream updates
echo -e "\nChecking for upstream updates on the ${TERMINUS_ENV} multidev..."
# the output goes to stderr, not stdout
UPSTREAM_UPDATES="$(terminus upstream:updates:list $SITE_UUID.$TERMINUS_ENV  --format=list  2>&1)"

if [[ ${UPSTREAM_UPDATES} == *"No updates"* ]]
then
    # no upstream updates available
    echo -e "\nNo upstream updates found on the ${TERMINUS_ENV} multidev..."
else
    # making sure the multidev is in git mode
    echo -e "\nSetting the ${TERMINUS_ENV} multidev to git mode"
    terminus connection:set $SITE_UUID.$TERMINUS_ENV git

    # apply Drupal upstream updates
    echo -e "\nApplying upstream updates on the ${TERMINUS_ENV} multidev..."
    terminus upstream:updates:apply $SITE_UUID.$TERMINUS_ENV --yes --updatedb --accept-upstream
    UPDATES_APPLIED=true
fi

# making sure the multidev is in SFTP mode
echo -e "\nSetting the ${TERMINUS_ENV} multidev to SFTP mode"
terminus connection:set $SITE_UUID.$TERMINUS_ENV sftp

# check for Drupal module updates
echo -e "\nChecking for Drupal module updates on the ${TERMINUS_ENV} multidev..."
PLUGIN_UPDATES="$(terminus drush $SITE_UUID.$TERMINUS_ENV -- pm-updatestatus --format=list)"

if [[ ${PLUGIN_UPDATES} == "" ]]
then
    # no Drupal module updates found
    echo -e "\nNo Drupal module updates found on the ${TERMINUS_ENV} multidev..."
else
    # update Drupal modules
    echo -e "\nUpdating Drupal modules on the ${TERMINUS_ENV} multidev..."
    terminus drush $SITE_UUID.$TERMINUS_ENV -- pm-updatecode --no-core --yes

    # wake the site environment before committing code
    echo -e "\nWaking the ${TERMINUS_ENV} multidev..."
    terminus env:wake -n $SITE_UUID.$TERMINUS_ENV

    # committing updated Drupal modules
    echo -e "\nCommitting Drupal modules updates on the ${TERMINUS_ENV} multidev..."
    terminus env:commit $SITE_UUID.$TERMINUS_ENV --message="Updates for the following Drupal modules: ${PLUGIN_UPDATES}" --yes
    UPDATES_APPLIED=true
   
    
fi

if [[ "${UPDATES_APPLIED}" = false ]]
then
    # no updates applied
    echo -e "\nNo updates to apply..."
    SLACK_MESSAGE="No updates on build #${CIRCLE_BUILD_NUM} for ${CIRCLE_PROJECT_USERNAME}. I'm going back to sleep."
    echo -e "\nSending a message to the ${SLACK_CHANNEL} Slack channel"
    curl -X POST --data "payload={\"channel\": \"${SLACK_CHANNEL}\", \"username\": \"${SLACK_USERNAME}\", \"text\": \"${SLACK_MESSAGE}\"}" $SLACK_HOOK_URL
else
    # updates applied, carry on

    # install node dependencies
    echo -e "\nRunning npm install..."
    npm install

    # ping the multidev environment to wake it from sleep
    echo -e "\nPinging the ${TERMINUS_ENV} multidev environment to wake it from sleep..."
    terminus env:wake -n $SITE_UUID.$TERMINUS_ENV

    # backstop visual regression
    echo -e "\nRunning BackstopJS tests..."
    backstop reference
    VISUAL_REGRESSION_RESULTS=$(backstop test || echo 'true')

    echo "${VISUAL_REGRESSION_RESULTS}"

    cd -
    if [[ ${VISUAL_REGRESSION_RESULTS} == *"Mismatch errors found"* ]]
    then
        # Visual Regression Failed. Get Visual Difference Image
        VISUAL_IMAGE_URL=$(php -f bin/post-image.php `find . | grep png | grep failed`)

        echo -e "\nVisual regression tests failed! Please manually check the ${TERMINUS_ENV} multidev..."
        SLACK_MESSAGE="Circle CI update check #${CIRCLE_BUILD_NUM} by ${CIRCLE_PROJECT_USERNAME}. Visual regression tests failed on <https://dashboard.pantheon.io/sites/${SITE_UUID}#${TERMINUS_ENV}/code|the ${TERMINUS_ENV} environment>! Please review and manually - ${VISUAL_IMAGE_URL}"
        echo -e "\nSending a message to the ${SLACK_CHANNEL} Slack channel"
        curl -X POST --data "payload={\"channel\": \"${SLACK_CHANNEL}\", \"username\": \"${SLACK_USERNAME}\", \"text\": \"${SLACK_MESSAGE}\"}" $SLACK_HOOK_URL
        exit 1
    else
        # visual regression passed
        echo -e "\nVisual regression tests passed between the ${TERMINUS_ENV} multidev and live."

        # enable git mode on dev
        echo -e "\nEnabling git mode on the dev environment..."
        terminus connection:set $SITE_UUID.dev git

        # merge the multidev back to dev
        echo -e "\nMerging the ${TERMINUS_ENV} multidev back into the dev environment (master)..."
        terminus connection:set $SITE_UUID.dev git
        
        # deploy to test
        echo -e "\nDeploying the updates from dev to test..."
        terminus env:deploy $SITE_UUID.test --sync-content --cc --note="Auto deploy of Drupal updates (core, modules)" --updatedb

        # backup the live site
        echo -e "\nBacking up the live environment..."
        terminus backup:create $SITE_UUID.live --element=all --keep-for=30

        # deploy to live
        echo -e "\nDeploying the updates from test to live..."
        terminus env:deploy $SITE_UUID.live --cc --note="Auto deploy of Drupal updates (core, modules)" --updatedb


        echo -e "\nVisual regression tests passed! Drupal updates deployed to live..."
        SLACK_MESSAGE="I've updated ${CIRCLE_PROJECT_REPONAME} on build #${CIRCLE_BUILD_NUM} and the visual regression tests passed! Drupal updates deployed to <https://dashboard.pantheon.io/sites/${SITE_UUID}#live/deploys|the live environment>."
        echo -e "\nSending a message to the ${SLACK_CHANNEL} Slack channel"
        curl -X POST --data "payload={\"channel\": \"${SLACK_CHANNEL}\", \"username\": \"${SLACK_USERNAME}\", \"text\": \"${SLACK_MESSAGE}\"}" $SLACK_HOOK_URL
    fi
fi
