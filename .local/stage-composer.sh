#!/usr/bin/env bash
# Applies stage branch overrides before `composer install`.
#
# Default behaviour: every package in "require" with version "dev-main" is
# automatically switched to "dev-develop".
#
# Exceptions (non-standard branch names) can be declared in composer.json:
#   "extra": {
#       "stage-overrides": {
#           "vendor/plugin": "dev-staging"
#       }
#   }
# Packages listed there take precedence over the auto-switch logic.

DIR="$( realpath -e -- "$( dirname -- "${BASH_SOURCE[0]}"; )"; )"

if [[ $DIR == $PWD ]]; then
    cd ..
fi

PACKAGES=$(php -r "
\$json = json_decode(file_get_contents('composer.json'), true);
\$require   = \$json['require'] ?? [];
\$overrides = \$json['extra']['stage-overrides'] ?? [];

\$result = \$overrides;

foreach (\$require as \$pkg => \$ver) {
    if (\$ver === 'dev-main' && !isset(\$result[\$pkg])) {
        \$result[\$pkg] = 'dev-develop';
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
