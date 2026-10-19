<?php

declare(strict_types=1);

namespace Deployer;

set('console', 'bin/console');
set('rsync', [
    'exclude'       => [],
    'exclude-file'  => dirname(__DIR__) . '/.deployignore',
    'include'       => [],
    'include-file'  => false,
    'filter'        => [],
    'filter-file'   => false,
    'filter-perdir' => false,
    'flags'         => 'rzE',
    'options'       => [
        'delete',
        'links',
    ],
    'timeout' => null,
]);

task('sw:deployment:helper', static function (): void {
    run('cd {{release_path}} && vendor/bin/shopware-deployment-helper run', ['timeout' => null]);
});

task('sw:health_checks', static function (): void {
    run('cd {{release_path}} && {{bin/php}} {{console}} system:check --context=pre_rollout');
});

task('shopware6:apps:install_update', function (): void {
    run('cd {{release_path}} && {{bin/php}} {{console}} app:refresh --activate --force');
});

task('shopware6:maintenance:enable', function (): void {
    run('cd {{release_path}} && {{bin/php}} {{console}} sales-channel:maintenance:enable --all', ['timeout' => null]);
});

task('shopware6:maintenance:disable', function (): void {
    run('cd {{release_path}} && {{bin/php}} {{console}} sales-channel:maintenance:disable --all', ['timeout' => null]);
});

task('shopware6:messenger:stop', function (): void {
    if (has('previous_release')) {
        run('cd {{previous_release}} && {{bin/php}} {{console}} messenger:stop-workers', ['timeout' => null]);
    }
});
