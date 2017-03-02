#!/bin/bash
set -e

prj_path=$(cd $(dirname $0); pwd -P)
devops_prj_path="$prj_path/devops"
template_path="$prj_path/template"   

load_init_module=1
# define: load_init_module
# defined: init_config_by_developer_name / load_config_for_dev / load_config_for_deploy / do_init_for_dev / clean_init_data

acme_path="$prj_path/acme"
prj_tmp_path="$prj_path/tmp"
dev_config_file="$prj_tmp_path/auto-gen.manager.config"

configsrv_image=liaohuqiu/configsrv
nginx_image=nginx:1.11

container_app_path='/ssl-auto'
container_app_static_path='/ssl-auto-static'

init_config_by_developer_name() {
    app=$developer_name-ssl

    app_container=$app-app
    nginx_container=$app-nginx

    app_storage_path=/opt/data/$app
    app_nginx_config_path="$app_storage_path/nginx-config"
    cert_path="$app_storage_path/cert"

    ensure_dir "$prj_tmp_path"
    ensure_dir "$app_storage_path"
    ensure_dir "$app_nginx_config_path"
    ensure_dir "$cert_path"
}

do_init_for_dev() {
    local config_key="sslgenerate.vars.site_list.$developer_name"
    local template_file="$template_path/manager.config.template"
    local config_file_name="sites-config"
    local dst_file=$dev_config_file
    local extra_kv_list="developer_name=$developer_name"

    render_server_config $config_key $template_file $config_file_name $dst_file

    template_file="$template_path/auto-ssl.dev.nginx.conf"
    dst_file="$app_nginx_config_path/auto-ssl.conf"

    render_server_config $config_key $template_file $config_file_name $dst_file $extra_kv_list
}

_config_file_tip() {
    echo "Please put your config file here: $1"
}

_load_config_file() {
    local config_file=$1
    if [ ! -f $config_file ]; then
        _config_file_tip "$config_file"
        exit 1
    fi
    domain_list=$(read_kv_config "$config_file" "domain_list")
    dnspod_id=$(read_kv_config "$config_file" "dnspod_id")
    dnspod_key=$(read_kv_config "$config_file" "dnspod_key")

    if [ -z "$domain_list" ] || [ -z "$dnspod_id" ] || [ -z "$dnspod_key" ]; then
        _config_file_tip "$config_file"
        exit 1
    fi
}


load_config_for_dev() {
    local config_file="$prj_path/env-config/config.dev"
    _load_config_file $config_file
    app_http_port=$(read_kv_config "$dev_config_file" "app_http_port")
}

load_config_for_deploy() {
    local config_file="$prj_path/env-config/config.$env"
    _load_config_file $config_file
    app_http_port=$(read_kv_config "$config_file" "app_http_port")

    run_cmd "cp $template_path/auto-ssl.nginx.conf $app_nginx_config_path/auto-ssl.conf"
}

source $devops_prj_path/base.sh

clean() {
    stop
    clean_init_data 
    local cmd="rm -rf $app_storage_path"
    _sudo_for_stroage "$cmd"
}

_sudo_for_stroage() {
    local cmd=$1
    run_cmd "docker run --rm $docker_run_fg_mode -v /opt/data:/opt/data $nginx_image bash -c '$cmd'"
}

run_nginx() {

    local nginx_data_dir="$prj_path/nginx-data"
    local nginx_log_path="$app_storage_path/logs/nginx"

    args="--restart=always"

    args="$args -p $app_http_port:80"

    # nginx config
    args="$args -v $nginx_data_dir/conf/nginx.conf:/etc/nginx/nginx.conf"

    # for the other sites
    args="$args -v $nginx_data_dir/conf/extra/:/etc/nginx/extra"

    # generated nginx docker sites config
    args="$args -v $app_nginx_config_path:/etc/nginx/docker-sites"

    # nginx certificate
    args="$args -v $nginx_data_dir/ssl-cert/:/etc/nginx/ssl-cert"

    # logs
    args="$args -v $nginx_log_path:/var/log/nginx"

    args="$args --volumes-from $app_container"

    args="$args --link $app_container:app"

    run_cmd "docker run -d $args --name $nginx_container $nginx_image"
}

stop_nginx() {
    stop_container $nginx_container
}

restart_nginx() {
    stop_nginx
    run_nginx
}
    
_run_app_container() {
    local cmd=$1
    args="$args --restart always"
    args="$args -v $prj_path:$container_app_path"
    args="$args -v $cert_path:$container_app_static_path/cert"

    args="$args -w $container_app_path"
    args="$args -e 'DOMAIN_LIST=$domain_list'"
    args="$args -e 'DNSPOD_Id=$dnspod_id'"
    args="$args -e 'DNSPOD_Key=$dnspod_key'"

    run_cmd "docker run $args -d --name $app_container $configsrv_image bash -c '$cmd'"
}

run_app() {
    local cmd='python src/manage.py runserver 0.0.0.0:8000'
    _run_app_container "$cmd"
}

_send_cmd_to_app() {
    local cmd=$1
    run_cmd "docker exec $docker_run_fg_mode $app_container bash -c '$cmd'"
}

to_app() {
    local cmd='bash'
    _send_cmd_to_app "$cmd"
}

stop_app() {
    stop_container $app_container
}

run() {
    run_app
    run_nginx
}

stop() {
    stop_app
    stop_nginx
}

restart() {
    stop
    run
}

#dns auto generater
dns_file() {
    domain=$(_loadfile)
    run_cmd "sh $acme_path/acme.sh --issue $domain" 
}

#dns load one
dns_one() {
    cmd="$2"
    if [ -z "$cmd" ]; then
        echo 'not domain-url'
        return
    else
        run_cmd "sh $acme_path/acme.sh --issue --dns dns_dp -d $cmd --debug 2"
    fi
}

help() {
cat <<EOF
    Usage: manage.sh [options]

        Valid options are:

        init_dev        [developer_name], env will 'dev'
        clean
        deploy          [env], developer_name will be the env

        build_app
        run_app
        to_app
        stop_app
        restart_app

        run
        stop
        restart

        run_nginx
        stop_nginx
        restart_nginx

        dns_one
        dns_file
        help                show this message
EOF
}

ALL_COMMANDS="init clean deploy"
ALL_COMMANDS="$ALL_COMMANDS build_app run_app stop_app to_app restart_app"
ALL_COMMANDS="$ALL_COMMANDS run_nginx stop_nginx restart_nginx"
ALL_COMMANDS="$ALL_COMMANDS run stop restart"
ALL_COMMANDS="$ALL_COMMANDS dns_one dns_file"

list_contains ALL_COMMANDS "$action" || action=help
$action "$@"
build_app
