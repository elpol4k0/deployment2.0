# Variables
PHP_BIN = php
NPM_BIN = npm
COMPOSER_BIN = composer
CONSOLE_BIN = $(PHP_BIN) bin/console
SHOPWARE_CLI_BIN = shopware-cli
AI_SYNC_SCRIPT = .ai/harness/ai-sync.sh

# Paths
DEPLOYMENT_PATH = .deployment
STOREFRONT_PATH = vendor/shopware/storefront/Resources/app/storefront
ADMIN_PATH = vendor/shopware/administration/Resources/app/administration

# Optional parameters (usage: make <target> PARAMS="--dry-run")
PARAMS =

# Default target
.PHONY: help
help:
	@echo "Please use 'make <target>' where <target> is one of:"
	@printf "  %-35s %s\n" "deployment-install" "First install the deployment dependencies and setup Shopware"
	@printf "  %-35s %s\n" "deployment-update-composer" "Update the deployment dependencies"
	@printf "  %-35s %s\n" "deployment-update-plugin" "Update a specific plugin"
	@printf "  %-35s %s\n" "deployment-use-staging" "Use development branch of self made plugins"
	@printf "  %-35s %s\n" "deployment-use-prod" "Use production branch of self made plugins"
	@printf "  %-35s %s\n" "rector" "Run Rector (apply automated refactorings)"
	@printf "  %-35s %s\n" "rector-dry" "Run Rector (dry-run, no changes)"
	@printf "  %-35s %s\n" "phpstan" "Run PHPStan static analysis"
	@printf "  %-35s %s\n" "cs-fix" "Run PHP-CS-Fixer (fix mode)"
	@printf "  %-35s %s\n" "cs-check" "Run PHP-CS-Fixer (dry-run / check mode)"
	@printf "  %-35s %s\n" "phpunit" "Run PHPUnit tests"
	@printf "  %-35s %s\n" "check-ci" "Run PHPStan, PHP-CS-Fixer and PHPUnit"
	@printf "  %-35s %s\n" "eslint" "Run ESLint"
	@printf "  %-35s %s\n" "ludtwig" "Run ludtwig Twig template linter"
	@printf "  %-35s %s\n" "cache-clear" "Clear Shopware cache"
	@printf "  %-35s %s\n" "cache-warmup" "Warm up Shopware cache"
	@printf "  %-35s %s\n" "build-storefront" "Build the Shopware Storefront (via shopware-cli)"
	@printf "  %-35s %s\n" "build-admin" "Build the Shopware Administration (via shopware-cli)"
	@printf "  %-35s %s\n" "watch-storefront" "Watch and reload the Storefront for development"
	@printf "  %-35s %s\n" "watch-admin" "Watch and reload the Administration for development"
	@printf "  %-35s %s\n" "build-js" "Build both Storefront and Administration"
	@printf "  %-35s %s\n" "ai-init" "Ensure .ai submodule is loaded, then delegate harness setup to .ai"
	@printf "  %-35s %s\n" "ai-sync" "Delegate full AI projection sync to .ai"
	@printf "  %-35s %s\n" "ai-sync-copilot" "Delegate Copilot projection sync to .ai"
	@printf "  %-35s %s\n" "ai-sync-codex" "Delegate Codex projection sync to .ai"
	@printf "  %-35s %s\n" "ai-sync-opencode" "Delegate OpenCode projection sync to .ai"
	@printf "  %-35s %s\n" "ai-doctor" "Delegate AI health checks to .ai"
	@printf "  %-35s %s\n" "shell-completion" "Print shell completion script for make targets"

# Targets
.PHONY: deployment-install
deployment-install:
	@cd $(DEPLOYMENT_PATH) && $(COMPOSER_BIN) install
	@$(COMPOSER_BIN) install --no-scripts
	@$(COMPOSER_BIN) bin all install --no-scripts
	@$(COMPOSER_BIN) symfony:recipes:install --yes --no-interaction
	@chmod 755 bin/*
	@chmod 755 .local/*
	@$(CONSOLE_BIN) system:setup --force
	@$(CONSOLE_BIN) system:install --create-database --basic-setup --shop-locale=de-DE
	@$(MAKE) build-js

.PHONY: deployment-update-composer
deployment-update-composer:
	@cd $(DEPLOYMENT_PATH) && $(COMPOSER_BIN) install
	@$(COMPOSER_BIN) install --no-scripts

.PHONY: deployment-update-plugin
deployment-update-plugin:
	@read -p "Enter plugin composer name: " name; \
	$(COMPOSER_BIN) update --no-scripts --ignore-platform-reqs "$$name"

.PHONY: deployment-use-staging
deployment-use-staging:
	@.local/stage-composer.sh
	@$(COMPOSER_BIN) update --no-scripts

.PHONY: deployment-use-prod
deployment-use-prod:
	@.local/prod-composer.sh
	@$(COMPOSER_BIN) update --no-scripts

.PHONY: phpstan
phpstan:
	@vendor-bin/phpstan/vendor/bin/phpstan analyse -c phpstan.neon $(PARAMS)

.PHONY: cs-fix
cs-fix:
	@vendor-bin/cs-fixer/vendor/bin/php-cs-fixer fix -v $(PARAMS)

.PHONY: cs-check
cs-check:
	@vendor-bin/cs-fixer/vendor/bin/php-cs-fixer fix -v --dry-run $(PARAMS)

.PHONY: phpunit
phpunit:
	@vendor/bin/phpunit $(PARAMS)

.PHONY: rector
rector:
	@vendor-bin/rector/vendor/bin/rector process $(PARAMS)

.PHONY: rector-dry
rector-dry:
	@vendor-bin/rector/vendor/bin/rector process --dry-run $(PARAMS)

.PHONY: eslint
eslint:
	@$(NPM_BIN) ci
	@npx eslint custom/ $(PARAMS)

.PHONY: check-ci
check-ci:
	@$(MAKE) cs-check
	@$(MAKE) phpstan
	@$(MAKE) phpunit

.PHONY: ludtwig
ludtwig:
	@ludtwig custom/ $(PARAMS)

.PHONY: cache-clear
cache-clear:
	@$(CONSOLE_BIN) cache:clear

.PHONY: cache-warmup
cache-warmup:
	@$(CONSOLE_BIN) cache:warmup

# JS build targets (uses shopware-cli, consistent with CI)
.PHONY: build-storefront
build-storefront:
	@$(CONSOLE_BIN) bundle:dump
	@$(CONSOLE_BIN) feature:dump
	@$(SHOPWARE_CLI_BIN) project storefront-build
	@$(CONSOLE_BIN) asset:install
	@$(CONSOLE_BIN) theme:compile -a

.PHONY: build-admin
build-admin:
	@$(CONSOLE_BIN) bundle:dump
	@$(CONSOLE_BIN) feature:dump
	@$(SHOPWARE_CLI_BIN) project admin-build
	@$(CONSOLE_BIN) asset:install

.PHONY: watch-storefront
watch-storefront:
	@$(CONSOLE_BIN) feature:dump
	@$(CONSOLE_BIN) bundle:dump
	@$(CONSOLE_BIN) theme:dump
	@$(NPM_BIN) --prefix $(STOREFRONT_PATH) run hot-proxy

.PHONY: watch-admin
watch-admin:
	@$(CONSOLE_BIN) bundle:dump
	@$(CONSOLE_BIN) feature:dump
	@$(NPM_BIN) --prefix $(ADMIN_PATH) run dev

.PHONY: build-js
build-js: build-storefront build-admin

.PHONY: ai-submodule-ready
ai-submodule-ready:
	@test -f .gitmodules || (printf '.gitmodules is missing. Add the .ai submodule first.\n' >&2; exit 1)
	@grep -F '[submodule ".ai"]' .gitmodules >/dev/null || (printf 'No .ai submodule configured in .gitmodules. Add the .ai submodule first.\n' >&2; exit 1)
	@printf '%s\n' 'Ensuring .ai submodule is initialized...'
	@git submodule update --init --recursive .ai
	@test -f .ai/harness/ai-init.sh || (printf '.ai/harness/ai-init.sh is missing after submodule init.\n' >&2; exit 1)
	@test -f .ai/harness/ai-doctor.sh || (printf '.ai/harness/ai-doctor.sh is missing after submodule init.\n' >&2; exit 1)
	@test -f $(AI_SYNC_SCRIPT) || (printf '$(AI_SYNC_SCRIPT) is missing after submodule init.\n' >&2; exit 1)
	@chmod +x .ai/harness/ai-init.sh .ai/harness/ai-doctor.sh $(AI_SYNC_SCRIPT)

.PHONY: ai-init
ai-init: ai-submodule-ready
	@.ai/harness/ai-init.sh

.PHONY: ai-sync
ai-sync: ai-submodule-ready
	@$(AI_SYNC_SCRIPT) all

.PHONY: ai-sync-copilot
ai-sync-copilot: ai-submodule-ready
	@$(AI_SYNC_SCRIPT) copilot

.PHONY: ai-sync-codex
ai-sync-codex: ai-submodule-ready
	@$(AI_SYNC_SCRIPT) codex

.PHONY: ai-sync-opencode
ai-sync-opencode: ai-submodule-ready
	@$(AI_SYNC_SCRIPT) opencode

.PHONY: ai-doctor
ai-doctor: ai-submodule-ready
	@.ai/harness/ai-doctor.sh

.PHONY: shell-completion
shell-completion:
	@echo "# Add the following to your ~/.bashrc or ~/.zshrc:"
	@echo "# complete -W \"\$$(make -qp | awk -F':' '/^[a-zA-Z0-9][^\\$$#\\/\\t=]*:([^=]|\\$$)/ {split(\$$1,A,/ /);for(i in A)print A[i]}' | sort -u)\" make"
	@echo ""
	@echo "# Available targets:"
	@make -qp | awk -F':' '/^[a-zA-Z0-9][^$$#\/\t=]*:([^=]|$$)/ {split($$1,A,/ /);for(i in A)print A[i]}' | grep -v Makefile | sort -u
