<?php

declare(strict_types=1);

namespace Deployer;

require 'recipe/common.php';
require 'contrib/rsync.php';
require 'recipe/composer.php';
require 'contrib/cachetool.php';
require 'deploy-shopware6.php';

// Deployer specific
set('application', '[PROJECTNAME]');
set('bin/php', '/usr/bin/php');
set('writable_mode', 'chmod');
add('shared_files', [
    '.env',
    'public/.htaccess',
    'public/.user.ini',
    'install.lock',
    'public/robots.txt',
]);
add('executable_files', ['bin/console']);
add('shared_dirs', [
    'config/jwt',
    'files',
    'var/log',
    'public/media',
    'public/sitemap',
    'public/thumbnail',
]);
add('writable_dirs', [
    'var/cache',
    'var/log',
    'files',
    'public/media',
    'public/thumbnail',
    'public/sitemap',
    'public/theme',
    'public/bundles',
]);
set('allow_anonymous_stats', false);
set('keep_releases', 5);
set('default_timeout', 600);
set('ssh_multiplexing', false);

// Shopware version is auto-detected by shopware-deployment-helper (supports SW 6.6 and 6.7)

// Shopware / deployment specific
// source => target -- Will copy the source into the target during build
set('source_directory', '../');

after('deploy:failed', 'deploy:unlock');

host('staging')
    ->setRemoteUser('[SSH_USER]')
    ->setHostname('[IP_STAGE]')
    ->setPort(22)
    ->set('stage', 'staging')
    ->set('branch', 'develop')
    ->set('deploy_path', '/var/www/share/[DOMAIN_STAGE]')
    ->set('rsync_src', '{{source_directory}}')
    ->set('rsync_dest', '{{release_path}}')
    ->set('app_url', 'https://[DOMAIN_STAGE]/')
    ->set('cachetool', '/var/run/php8.3-fpm-[DOMAIN_STAGE].sock')
    ->set('composer_options', 'install --verbose --prefer-dist --no-progress --no-interaction --optimize-autoloader --no-scripts');

host('production')
    ->setRemoteUser('[SSH_USER]')
    ->setHostname('[IP_LIVE]')
    ->setPort(22)
    ->set('stage', 'production')
    ->set('branch', 'main')
    ->set('deploy_path', '/var/www/share/[DOMAIN_LIVE]')
    ->set('rsync_src', '{{source_directory}}')
    ->set('rsync_dest', '{{release_path}}')
    ->set('app_url', 'https://[DOMAIN_LIVE]/')
    ->set('cachetool', '/var/run/php8.3-fpm-[DOMAIN_LIVE].sock')
    ->set('composer_options', 'install --verbose --prefer-dist --no-progress --no-interaction --no-dev --optimize-autoloader --no-scripts');

task('deploy', [
    'deploy:info',
    'deploy:setup',
    'deploy:lock',
    'deploy:release',
    'rsync',
    'deploy:shared',
    'deploy:writable',
    'shopware6:maintenance:enable',
    'sw:deployment:helper',
    // Uncomment if your project uses Shopware Apps:
    // 'shopware6:apps:install_update',
    'sw:health_checks',
    'deploy:symlink',
    'shopware6:maintenance:disable',
    'shopware6:messenger:stop',
    'cachetool:clear:opcache',
    'deploy:unlock',
    'deploy:cleanup',
    'deploy:success',
])->desc('Deploy your project');
