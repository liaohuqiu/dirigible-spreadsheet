#!/bin/bash

# define: load_init_module
# defined: init_config_by_developer_name / load_config_for_dev / load_config_for_deploy / do_init_for_dev / clean_init_data
# $developer_name will be defined
manager_config_file="$devops_prj_path/auto-gen.developer-name.config"

function clean_init_data() {
    run_cmd "rm -rf $manager_config_file"
}

function _try_load_config() {
    if [ ! -f "$manager_config_file" ]; then
        echo 'Config file is not found, please call `sh manager.sh init_dev developer_name` first.'
        exit 1
    fi
    source $manager_config_file
    # $developer_name will be defined now
    load_config_for_dev
}

function init_dev() {
    echo "developer_name: $developer_name"
    echo "developer_name=$developer_name" > $manager_config_file
    do_init_for_dev $developer_name
}

if [ "$load_init_module" == "1" ]; then
    if [ "$action" = 'deploy' ]; then
        if [ $# -lt 3 ]; then
            echo "Usage sh $0 deploy env cmd";
            exit 1
        fi
        env=$2
        if [ -z "$env" ]; then
            env='prod'
        fi
        developer_name=$env
        init_config_by_developer_name
        load_config_for_deploy
        action=$3
        return
    fi
    if [ "$action" = 'init_dev' ]; then
        if [ $# -lt 2 ]; then
            echo "Usage sh $0 init developer_name";
            exit 1
        fi
        env='dev'
        developer_name=$2
        init_config_by_developer_name
        init_dev
        exit 0
    else
        _try_load_config
        init_config_by_developer_name
    fi
fi
