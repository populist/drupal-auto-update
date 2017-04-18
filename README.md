# Pantheon Drupal Auto Update #

## Description ##
Automate Drupal core, plugin and theme updates on [Pantheon](https://pantheon.io) with Terminus, CircleCI, Drush, BackstopJS and Slack.

This script will:

1. Authenticate with [Terminus](https://github.com/pantheon-systems/terminus) via machine token
2. Delete the multidev environment `update-dr`
3. Recreate the multidev environment `update-dr`
	* Deletion and recreation is done to clear any existing changes and pull the latest database/files from the live environment 
4. Switch the multidev environment `update-dr` to Git mode
5. [Apply Pantheon upstream updates](https://pantheon.io/docs/upstream-updates/)
	* Drupal core updates are managed in the upstream
6. Switch the multidev environment `update-dr` to SFTP mode
7. Check for and apply Drupal plugin updates via [Drush](http://www.drush.org), if available
8. Check for and apply Drupal theme updates via [Drush](http://www.drush.org), if available
	* If no Drupal updates are available the script will complete and report the Slack
9. Use BackstopJS to run a visual regression test between the live environment and the multidev environment
	* If discrepencies are found the script will fail and report the error to Slack
10. Merge the multidev environment with the dev environment
11. Deploy the dev environment to the test environment
12. Deploy the test environment to the live environment
13. Post a success message to Slack

## License ##
[GPLv2 or later](http://www.gnu.org/licenses/gpl-2.0.html)

## Setup ##
1. Create a [CircleCI](https://circleci.com) project
2. Add [environment variables to CircleCI](https://circleci.com/docs/environment-variables/) for the following:
	* `SITE_UUID`: The [Pantheon site UUID](https://pantheon.io/docs/sites/#site-uuid)
	* `TERMINUS_MACHINE_TOKEN`: A [Pantheon Terminus machine token](https://pantheon.io/docs/machine-tokens/) with access to the site
	* `SLACK_URL`: The [Slack incoming webhook URL](https://api.slack.com/incoming-webhooks)
	* `SLACK_CHANNEL`: The Slack channel to post notifications to
3. Add an [SSH key to Pantheon](https://pantheon.io/docs/ssh-keys/) and [to the CircleCI project](https://circleci.com/docs/permissions-and-access-during-deployment/).
4. Update the site UUID in the `.env` file
5. Update _scenarios_ in `backstop.js` with URLs for pages you wish to check with visual regression
	* `url` refers to the live URL and `referenceUrl` refers to the same page on the Pantheon multidev environment
6. Ping the [CircleCI API](https://circleci.com/docs/api/) at the desired frequency, e.g. daily, to run the script

## Notes ##
This workflow assumes the `master` branch (dev) and test environments on Pantheon are always in a shippable state as the script will automatically deploy changes from dev to test and live.

All incomplete work should be kept in a [Pantheon multidev environment](https://pantheon.io/docs/multidev/), on a separate Git branch.


Inspired by [Andrew Taylor](https://github.com/ataylorme/) whose work on automatic updates for WordPress this project is based and [Kyle Hall](https://github.com/Ky1e) who brought joy and delight to Drupal utilizing Terminus 1.0. 
