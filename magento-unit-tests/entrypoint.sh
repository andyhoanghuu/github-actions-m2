#!/bin/bash

set -e

test -z "${MAGENTO_EDITION}" || MAGENTO_EDITION=$MAGENTO_EDITION
test -z "${CE_VERSION}" || MAGENTO_VERSION=$CE_VERSION

test -z "${MODULE_NAME}" && MODULE_NAME=$INPUT_MODULE_NAME
test -z "${COMPOSER_NAME}" && COMPOSER_NAME=$INPUT_COMPOSER_NAME
test -z "${MAGENTO_EDITION}" && MAGENTO_EDITION=$INPUT_MAGENTO_EDITION
test -z "${MAGENTO_VERSION}" && MAGENTO_VERSION=$INPUT_MAGENTO_VERSION

test -z "${MODULE_NAME}" && (echo "'module_name' is not set" && exit 1)
test -z "${COMPOSER_NAME}" && (echo "'composer_name' is not set" && exit 1)
test -z "${MAGENTO_EDITION}" && (echo "'magento_edition' is not set" && exit 1)
test -z "${MAGENTO_VERSION}" && (echo "'magento_version' is not set" && exit 1)

MAGENTO_ROOT=/tmp/m2
PROJECT_PATH=$GITHUB_WORKSPACE
test -z "${REPOSITORY_URL}" && REPOSITORY_URL="https://repo-magento-mirror.fooman.co.nz/"

echo "Setup Magento credentials"
test -z "${MAGENTO_MARKETPLACE_USERNAME}" || composer global config http-basic.repo.magento.com $MAGENTO_MARKETPLACE_USERNAME $MAGENTO_MARKETPLACE_PASSWORD

if [[ ! -z "$MAGENTO_EDITION" ]] ; then
    MAGENTO_EDITION="community"
fi
echo "Prepare composer installation for $MAGENTO_EDITION edition version $MAGENTO_VERSION"
composer create-project --repository=$REPOSITORY_URL --no-install --no-progress --no-plugins "magento/project-${MAGENTO_EDITION}-edition" $MAGENTO_ROOT "$MAGENTO_VERSION"

echo "Setup extension source folder within Magento root"
cd $MAGENTO_ROOT
mkdir -p local-source/
cd local-source/
cp -R ${GITHUB_WORKSPACE}/${MODULE_SOURCE} $MODULE_NAME

echo "Configure extension source in composer"
cd $MAGENTO_ROOT
composer config repositories.local-source path local-source/\*
composer require $COMPOSER_NAME:@dev --no-update --no-interaction

if [[ ! -z "$INPUT_MAGENTO_PRE_INSTALL_SCRIPT" && -f "${GITHUB_WORKSPACE}/$INPUT_MAGENTO_PRE_INSTALL_SCRIPT" ]] ; then
    echo "Running custom pre-installation script: ${INPUT_MAGENTO_PRE_INSTALL_SCRIPT}"
    . ${GITHUB_WORKSPACE}/$INPUT_MAGENTO_PRE_INSTALL_SCRIPT
fi

echo "Run installation"
COMPOSER_MEMORY_LIMIT=-1 composer install --prefer-dist --no-interaction --no-progress --no-suggest

echo "Determine which phpunit.xml file to use"
if [[ -z "$INPUT_PHPUNIT_FILE" || ! -f "$INPUT_PHPUNIT_FILE" ]] ; then
    INPUT_PHPUNIT_FILE=/docker-files/phpunit.xml
fi

echo "Using PHPUnit file: $INPUT_PHPUNIT_FILE"
echo "Prepare for unit tests"
cd $MAGENTO_ROOT
sed "s#%COMPOSER_NAME%#$COMPOSER_NAME#g" $INPUT_PHPUNIT_FILE > dev/tests/unit/phpunit.xml

echo "Run the unit tests"
cd $MAGENTO_ROOT/dev/tests/unit && ../../../vendor/bin/phpunit -c phpunit.xml

