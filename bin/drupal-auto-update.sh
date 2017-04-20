#!/bin/bash

UPDATES_APPLIED=false

# login to Terminus
php -f bin/slack_notify.php terminus_login
echo -e "\nLogging into Terminus..."
terminus auth:login --machine-token=${TERMINUS_MACHINE_TOKEN}

# setup the multidev environment
php -f bin/slack_notify.php pantheon_multidev_setup
echo -e "\nDeleting the ${TERMINUS_ENV} multidev environment..."
terminus multidev:delete $SITE_UUID.$TERMINUS_ENV --delete-branch --yes
echo -e "\nRe-creating the ${TERMINUS_ENV} multidev environment..."
terminus multidev:create $SITE_UUID.live $TERMINUS_ENV

# check for upstream updates
echo -e "\nChecking for upstream updates on the ${TERMINUS_ENV} multidev..."
php -f bin/slack_notify.php drupal_updates
UPSTREAM_UPDATES="$(terminus upstream:updates:list $SITE_UUID.$TERMINUS_ENV  --format=yaml)"

if [[ ${UPSTREAM_UPDATES} == "{  }" ]]
then
    # no upstream updates available
    echo -e "\nNo upstream updates found on the ${TERMINUS_ENV} multidev..."
    php -f bin/slack_notify.php drupal_no_coreupdates
else
    # making sure the multidev is in git mode
    echo -e "\nSetting the ${TERMINUS_ENV} multidev to git mode"
    terminus connection:set $SITE_UUID.$TERMINUS_ENV git

    # apply Drupal upstream updates
    echo -e "\nApplying upstream updates on the ${TERMINUS_ENV} multidev..."
    php -f bin/slack_notify.php drupal_coreupdates 
    php -f bin/slack_notify.php terminus_coreupdates 
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
    php -f bin/slack_notify.php drupal_no_moduleupdates
else
    # update Drupal modules
    echo -e "\nUpdating Drupal modules on the ${TERMINUS_ENV} multidev..."
    php -f bin/slack_notify.php drupal_moduleupdates ${PLUGIN_UPDATES}
    php -f bin/slack_notify.php terminus_moduleupdates
    terminus drush $SITE_UUID.$TERMINUS_ENV -- pm-updatecode --no-core --yes

    # wake the site environment before committing code
    echo -e "\nWaking the ${TERMINUS_ENV} multidev..."
    terminus env:wake -n $SITE_UUID.$TERMINUS_ENV

    # committing updated Drupal modules
    echo -e "\nCommitting Drupal modules updates on the ${TERMINUS_ENV} multidev..."
    terminus env:commit $SITE_UUID.$TERMINUS_ENV --force --message="Updates for the following Drupal modules: ${PLUGIN_UPDATES}" --yes
    UPDATES_APPLIED=true
fi

if [[ "${UPDATES_APPLIED}" = false ]]
then
    # no updates applied
    echo -e "\nNo updates to apply..."
    php -f bin/slack_notify.php wizard_noupdates
else
    # updates applied, carry on
    php -f bin/slack_notify.php wizard_updates

    # ping the multidev environment to wake it from sleep
    echo -e "\nPinging the ${TERMINUS_ENV} multidev environment to wake it from sleep..."
    terminus env:wake -n $SITE_UUID.$TERMINUS_ENV

    # backstop visual regression
    echo -e "\nRunning BackstopJS tests..."
    php -f bin/slack_notify.php visual
    backstop reference
    VISUAL_REGRESSION_RESULTS=$(backstop test || echo 'true')

    echo "${VISUAL_REGRESSION_RESULTS}"

    if [[ ${VISUAL_REGRESSION_RESULTS} == *"Mismatch errors found"* ]]
    then
        # Visual Regression Failed. Get Visual Difference Image
        echo -e "\nVisual regression tests failed! Please manually check the ${TERMINUS_ENV} multidev..."
        php -f bin/slack_notify.php visual_different `find . | grep png | grep failed`
        exit 1
    else
        # visual regression passed
        echo -e "\nVisual regression tests passed between the ${TERMINUS_ENV} multidev and live."
        php -f bin/slack_notify.php visual_same

        # enable git mode on dev
        echo -e "\nEnabling git mode on the dev environment..."
        terminus connection:set $SITE_UUID.dev git

        # merge the multidev back to dev
        echo -e "\nMerging the ${TERMINUS_ENV} multidev back into the dev environment (master)..."
        php -f bin/slack_notify.php pantheon_deploy dev
        terminus multidev:merge-to-dev $SITE_UUID.$TERMINUS_ENV
        
        # deploy to test
        echo -e "\nDeploying the updates from dev to test..."
        php -f bin/slack_notify.php pantheon_deploy test
        terminus env:deploy $SITE_UUID.test --sync-content --cc --note="Auto deploy of Drupal updates (core, modules)" --updatedb

        # backup the live site
        echo -e "\nBacking up the live environment..."
        php -f bin/slack_notify.php pantheon_backup
        terminus backup:create $SITE_UUID.live --element=all --keep-for=30

        # deploy to live
        echo -e "\nDeploying the updates from test to live..."
        php -f bin/slack_notify.php pantheon_deploy live
        terminus env:deploy $SITE_UUID.live --cc --note="Auto deploy of Drupal updates (core, modules)" --updatedb

        echo -e "\nVisual regression tests passed! Drupal updates deployed to live..."
        php -f bin/slack_notify.php wizard_done `find . | grep document_0_desktop | grep test`
    fi
fi
