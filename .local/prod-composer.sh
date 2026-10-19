#!/usr/bin/env bash
# Refreshes production branch references before `composer install`.
#
# The versions in composer.json "require" are already the production ones, but
# composer.lock pins a concrete commit per dev branch. Without re-requiring the
# packages, `composer install` would deploy that stale commit instead of the
# current head of the branch.
#
# Default behaviour: every package in "require" with version "dev-main" is
# required again as "dev-main", which re-resolves the branch to its newest
# commit.
#
# Exceptions (non-standard branch names) can be declared in composer.json:
#   "extra": {
#       "prod-overrides": {
#           "vendor/plugin": "dev-main67"
#       }
#   }
# Packages listed there take precedence over the auto-refresh logic.

DIR="$( realpath -e -- "$( dirname -- "${BASH_SOURCE[0]}"; )"; )"

if [[ $DIR == $PWD ]]; then
    cd ..
fi

PACKAGES=$(php -r "
\$json = json_decode(file_get_contents('composer.json'), true);
\$require   = \$json['require'] ?? [];
\$overrides = \$json['extra']['prod-overrides'] ?? [];

\$result = \$overrides;

foreach (\$require as \$pkg => \$ver) {
    if (\$ver === 'dev-main' && !isset(\$result[\$pkg])) {
        \$result[\$pkg] = 'dev-main';
    }
}

if (empty(\$result)) { exit(0); }
echo implode(' ', array_map(
    fn(\$p, \$v) => escapeshellarg(\$p.':'.\$v),
    array_keys(\$result), array_values(\$result)
));
")

if [ -n "$PACKAGES" ]; then
    composer require --no-scripts --ignore-platform-reqs --no-install $PACKAGES
fi
