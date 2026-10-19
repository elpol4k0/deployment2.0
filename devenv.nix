{ pkgs, inputs, lib, config, ... }:
# https://developer.shopware.com/docs/guides/installation/devenv.html#what-is-devenv
{
  packages = [
    pkgs.gnupatch
    pkgs.yalc
    pkgs.mysql-shell
    pkgs.mydumper
    inputs.froshpkgs.packages.${pkgs.system}.shopware-cli
  ];

  dotenv.disableHint = true;

  languages.javascript = {
    enable = lib.mkDefault true;
    package = lib.mkDefault pkgs.nodejs_24;
  };

  languages.php.enable = true;
  languages.php.version = "8.4";
  languages.php.extensions = [ "amqp" "redis" "grpc" "xdebug" "pdo_mysql" "mysqli" "zstd" ];
  languages.php.ini = ''
    memory_limit = 2048M
    max_execution_time = 3600
    pdo_mysql.default_socket = ''${MYSQL_UNIX_PORT}
    mysqli.default_socket = ''${MYSQL_UNIX_PORT}
    blackfire.agent_socket = "${config.services.blackfire.socket}"
    realpath_cache_ttl = 3600
    session.gc_probability = 0
    session.save_handler = redis
    session.save_path = "tcp://127.0.0.1:6379/0"
    display_errors = On
    error_reporting = E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED
    opcache.memory_consumption = 256M
    opcache.interned_strings_buffer = 20
    opcache.max_accelerated_files = 30000
    opcache.jit = tracing
    opcache.jit_buffer_size = 256M
    zend.assertions = 0
    short_open_tag = 0
    zend.detect_unicode = 0
    xdebug.mode = debug
    xdebug.start_with_request = trigger
    xdebug.client_host = 127.0.0.1
    xdebug.client_port = 9003
  '';

  languages.php.fpm.pools.web = {
    settings = {
      "clear_env" = "no";
      "pm" = "dynamic";
      "pm.max_children" = 20;
      "pm.start_servers" = 4;
      "pm.min_spare_servers" = 2;
      "pm.max_spare_servers" = 10;
      "pm.process_idle_timeout" = "60s";
      "request_terminate_timeout" = "0";
    };
  };

  services.caddy.enable = lib.mkDefault true;
  services.caddy.virtualHosts."http://[PROJECT].localhost" = {
    extraConfig = ''
      root * public
      php_fastcgi unix/${config.languages.php.fpm.pools.web.socket}
      file_server
    '';
  };

  services.mysql = {
    enable = true;
    package = pkgs.mysql84;
    initialDatabases = lib.mkDefault [{ name = "shopware"; }];
    ensureUsers = lib.mkDefault [
      {
        name = "shopware";
        password = "shopware";
        ensurePermissions = { "*.*" = "ALL PRIVILEGES"; };
      }
    ];
    settings = {
      mysqld = {
        group_concat_max_len = 320000;
        log_bin_trust_function_creators = 1;
        sql_mode = "STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION";
        innodb_buffer_pool_size = "512M";
        innodb_log_file_size = "128M";
        skip-log-bin = 1;
      };
    };
  };

  services.redis.enable = lib.mkDefault true;
  services.redis.port = 6379;
  services.mailhog.enable = lib.mkDefault true;
  # services.elasticsearch.enable = true;
  # services.rabbitmq.enable = true;
  # services.rabbitmq.managementPlugin.enable = true;OptionManagementService.php


  # Environment variables
  env.COMPOSER_HOME = "${toString ./.}/.composer";
  env.APP_URL = lib.mkDefault "http://[PROJECT].localhost";
  env.CYPRESS_baseUrl = lib.mkDefault "http://[PROJECT].localhost";
  env.DATABASE_URL = lib.mkDefault "mysql://root@localhost:3306/shopware";
  env.MAILER_DSN = lib.mkDefault "smtp://localhost:1025";
  env.SQL_SET_DEFAULT_SESSION_VARIABLES = lib.mkDefault "0";
  env.OPENSEARCH_URL = "localhost:9000";
  env.SHOPWARE_ES_INDEX_PREFIX = "sw";
  env.ESLINT_DISABLE=true;
  env.SHOPWARE_HTTP_CACHE_ENABLED = "1";
  env.SHOPWARE_HTTP_DEFAULT_TTL = "7200";

  processes = {
    queue-worker = {
      exec = "php -d memory_limit=512M bin/console messenger:consume --time-limit=300 async low_priority failed scheduler_shopware";
      restart = {
        on = "always";
        max = null;
      };
      after = [
        "devenv:processes:mysql@ready"
        "devenv:processes:phpfpm-web@started"
        "devenv:processes:redis@started"
      ];
    };

    scheduled-task-runner = {
      exec = "php -d memory_limit=256M bin/console scheduled-task:run";
      restart = {
        on = "always";
        max = null;
      };
      after = [
        "devenv:processes:mysql@ready"
        "devenv:processes:phpfpm-web@started"
      ];
    };
  };
}
