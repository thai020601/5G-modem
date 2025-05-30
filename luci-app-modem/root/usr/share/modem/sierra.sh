#!/bin/bash
# sierra.sh - EM9190 5G modem support for OpenWrt luci-app-modem
# Copyright (C) 2024 Sierra Wireless/Semtech

SCRIPT_DIR="/usr/share/modem"

#预设
sierra_presets()
{
	at_command='ATI'
	# sh "${SCRIPT_DIR}/modem_at.sh" "$at_port" "$at_command"
}

#获取DNS
# $1:AT串口
# $2:连接定义
quectel_get_dns()
{
    local at_port="$1"
    local define_connect="$2"

    [ -z "$define_connect" ] && {
        define_connect="1"
    }

    local public_dns1_ipv4="223.5.5.5"
    local public_dns2_ipv4="119.29.29.29"
    local public_dns1_ipv6="2400:3200::1" #下一代互联网北京研究中心：240C::6666，阿里：2400:3200::1，腾讯：2402:4e00::
    local public_dns2_ipv6="2402:4e00::"

    #获取DNS地址
    at_command="AT+GTDNS=${define_connect}"
    local response=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+GTDNS: ")

    local ipv4_dns1=$(echo "${response}" | awk -F'"' '{print $2}' | awk -F',' '{print $1}')
    [ -z "$ipv4_dns1" ] && {
        ipv4_dns1="${public_dns1_ipv4}"
    }

    local ipv4_dns2=$(echo "${response}" | awk -F'"' '{print $4}' | awk -F',' '{print $1}')
    [ -z "$ipv4_dns2" ] && {
        ipv4_dns2="${public_dns2_ipv4}"
    }

    local ipv6_dns1=$(echo "${response}" | awk -F'"' '{print $2}' | awk -F',' '{print $2}')
    [ -z "$ipv6_dns1" ] && {
        ipv6_dns1="${public_dns1_ipv6}"
    }

    local ipv6_dns2=$(echo "${response}" | awk -F'"' '{print $4}' | awk -F',' '{print $2}')
    [ -z "$ipv6_dns2" ] && {
        ipv6_dns2="${public_dns2_ipv6}"
    }

    dns="{
        \"dns\":{
            \"ipv4_dns1\":\"$ipv4_dns1\",
            \"ipv4_dns2\":\"$ipv4_dns2\",
            \"ipv6_dns1\":\"$ipv6_dns1\",
            \"ipv6_dns2\":\"$ipv6_dns2\"
	    }
    }"

    echo "$dns"
}

#获取拨号模式
# $1:AT串口
# $2:平台
sierra_get_mode()
{
    local at_port="$1"
    local platform="$2"

    local mode_num="2"

    if [ -z "$mode_num" ]; then
        echo "unknown"
        return
    fi

    #获取芯片平台
	if [ -z "$platform" ]; then
		local modem_number=$(uci -q get modem.@global[0].modem_number)
        for i in $(seq 0 $((modem_number-1))); do
            local at_port_tmp=$(uci -q get modem.modem${i}.at_port)
            if [ "$at_port" = "$at_port_tmp" ]; then
                platform=$(uci -q get modem.modem${i}.platform)
                break
            fi
        done
	fi
    
    local mode
    case "$platform" in
        "qualcomm")
            case "$mode_num" in
                "2") mode="mbim" ;;
                *) mode="${mode_num}" ;;
            esac
        ;;
        *)
            mode="${mode_num}"
        ;;
    esac
    echo "${mode}"
}

#设置拨号模式
# $1:AT串口
# $2:拨号模式配置
sierra_set_mode()
{
    local at_port="$1"

    #获取芯片平台
    local platform
    local modem_number=$(uci -q get modem.@global[0].modem_number)
    for i in $(seq 0 $((modem_number-1))); do
        local at_port_tmp=$(uci -q get modem.modem$i.at_port)
        if [ "$at_port" = "$at_port_tmp" ]; then
            platform=$(uci -q get modem.modem$i.platform)
            break
        fi
    done

    #获取拨号模式配置
    local mode_num
    case "$platform" in
        "qualcomm")
            case "$2" in
                #"qmi") mode_num="0" ;;
                # "gobinet")  mode_num="0" ;;
                #"ecm") mode_num="1" ;;
                "mbim") mode_num="2" ;;
                #"rndis") mode_num="3" ;;
                #"ncm") mode_num="5" ;;
                *) mode_num="0" ;;
            esac
        ;;
#        "unisoc")
#            case "$2" in
#                "ecm") mode_num="1" ;;
#                "mbim") mode_num="2" ;;
#                "rndis") mode_num="3" ;;
#                "ncm") mode_num="5" ;;
#                *) mode_num="0" ;;
#            esac
#        ;;
        *)
            mode_num="0"
        ;;
    esac

    #设置模组
    at_command='AT+QCFG="usbnet",'${mode_num}
    sh ${SCRIPT_DIR}/modem_at.sh "${at_port}" "${at_command}"
}

#获取网络偏好
# $1:AT串口
# $2:数据接口
# $3:模组名称
quectel_get_network_prefer()
{
    local at_port="$1"
    local data_interface="$2"
    local modem_name="$3"

    at_command='AT+QNWPREFCFG="mode_pref"'
    local response=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+QNWPREFCFG:" | sed 's/\r//g')
    local network_type_num=$(echo "$response" | awk -F',' '{print $2}')

    #获取网络类型
    # local network_prefer_2g="0";
    local network_prefer_3g="0";
    local network_prefer_4g="0";
    local network_prefer_5g="0";

    #匹配不同的网络类型
    local auto=$(echo "${response}" | grep "AUTO")
    if [ -n "$auto" ]; then
        network_prefer_3g="1"
        network_prefer_4g="1"
        network_prefer_5g="1"
    else
        local wcdma=$(echo "${response}" | grep "WCDMA")
        local lte=$(echo "${response}" | grep "LTE")
        local nr=$(echo "${response}" | grep "NR5G")
        if [ -n "$wcdma" ]; then
            network_prefer_3g="1"
        fi
        if [ -n "$lte" ]; then
            network_prefer_4g="1"
        fi
        if [ -n "$nr" ]; then
            network_prefer_5g="1"
        fi
    fi

    #获取频段信息
    # local band_2g_info="[]"
    local band_3g_info="[]"
    local band_4g_info="[]"
    local band_5g_info="[]"

    #生成网络偏好
    local network_prefer="{
        \"network_prefer\":[
            {\"3G\":{
                \"enable\":$network_prefer_3g,
                \"band\":$band_3g_info
            }},
            {\"4G\":{
                \"enable\":$network_prefer_4g,
                \"band\":$band_4g_info
            }},
            {\"5G\":{
                \"enable\":$network_prefer_5g,
                \"band\":$band_5g_info
            }}
        ]
    }"
    echo "${network_prefer}"
}

#设置网络偏好
# $1:AT串口
# $2:网络偏好配置
quectel_set_network_prefer()
{
    local at_port="$1"
    local network_prefer="$2"

     #获取网络偏好配置
    local network_prefer_config

    #获取选中的数量
    local count=$(echo "$network_prefer" | grep -o "1" | wc -l)
    #获取启用的网络偏好
    local enable_5g=$(echo "$network_prefer" | jq -r '.["5G"].enable')
    local enable_4g=$(echo "$network_prefer" | jq -r '.["4G"].enable')
    local enable_3g=$(echo "$network_prefer" | jq -r '.["3G"].enable')

    case "$count" in
        "1")
            if [ "$enable_3g" = "1" ]; then
                network_prefer_config="WCDMA"
            elif [ "$enable_4g" = "1" ]; then
                network_prefer_config="LTE"
            elif [ "$enable_5g" = "1" ]; then
                network_prefer_config="NR5G"
            fi
        ;;
        "2")
            if [ "$enable_3g" = "1" ] && [ "$enable_4g" = "1" ]; then
                network_prefer_config="WCDMA:LTE"
            elif [ "$enable_3g" = "1" ] && [ "$enable_5g" = "1" ]; then
                network_prefer_config="WCDMA:NR5G"
            elif [ "$enable_4g" = "1" ] && [ "$enable_5g" = "1" ]; then
                network_prefer_config="LTE:NR5G"
            fi
        ;;
        "3") network_prefer_config="AUTO" ;;
        *) network_prefer_config="AUTO" ;;
    esac

    #设置模组
    at_command='AT+QNWPREFCFG="mode_pref",'${network_prefer_config}
    sh ${SCRIPT_DIR}/modem_at.sh "${at_port}" "${at_command}"
}

#获取电压
# $1:AT串口
sierra_get_voltage()
{
    local at_port="$1"
    
    #Voltage（电压）
    at_command="AT+CBC"
	local voltage=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+CBC:" | awk -F',' '{print $3}' | sed 's/\r//g')
    echo "${voltage}"
}

#获取温度
# $1:AT串口
sierra_get_temperature()
{
    local at_port="$1"
    
    #Temperature（温度）
    at_command="AT!TMSTATUS?"

    while true; do
        response=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "^modem" | awk '{print $3}')
        [ $response -gt 0 ] && break
    done

    local temperature
	if [ -n "$response" ]; then
		temperature="${response}$(printf "\xc2\xb0")C"
	fi

    # response=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+QTEMP:")
    # QTEMP=$(echo $response | grep -o -i "+QTEMP: [0-9]\{1,3\}")
    # if [ -z "$QTEMP" ]; then
    #     QTEMP=$(echo $response | grep -o -i "+QTEMP:[ ]\?\"XO[_-]THERM[_-][^,]\+,[\"]\?[0-9]\{1,3\}" | grep -o "[0-9]\{1,3\}")
    # fi
    # if [ -z "$QTEMP" ]; then
    #     QTEMP=$(echo $response | grep -o -i "+QTEMP:[ ]\?\"MDM-CORE-USR.\+[0-9]\{1,3\}\"" | cut -d\" -f4)
    # fi
    # if [ -z "$QTEMP" ]; then
    #     QTEMP=$(echo $response | grep -o -i "+QTEMP:[ ]\?\"MDMSS.\+[0-9]\{1,3\}\"" | cut -d\" -f4)
    # fi
    # if [ -n "$QTEMP" ]; then
    #     CTEMP=$(echo $QTEMP | grep -o -i "[0-9]\{1,3\}")$(printf "\xc2\xb0")"C"
    # fi

    echo "${temperature}"
}

#获取连接状态
# $1:AT串口
# $2:连接定义
sierra_get_connect_status()
{
    local at_port="$1"
    local define_connect="$2"

    #默认值为1
    [ -z "$define_connect" ] && {
        define_connect="1"
    }

    at_command="AT+CGPADDR=1"
    local ipv4=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+CGPADDR: " | awk -F',' '{print $2}')
    local not_ip="0.0.0.0"

    #设置连接状态
    local connect_status
    if [ -z "$ipv4" ] || [[ "$ipv4" = *"$not_ip"* ]]; then
        connect_status="disconnect"
    else
        connect_status="connect"
    fi
    
    #方法二
    # at_command="AT+QNWINFO"

	# local response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+QNWINFO:")

    # local connect_status
	# if [[ "$response" = *"No Service"* ]]; then
    #     connect_status="disconnect"
    # elif [[ "$response" = *"Unknown Service"* ]]; then
    #     connect_status="disconnect"
    # else
    #     connect_status="connect"
    # fi

    echo "$connect_status"
}




sierra_base_info()
{
    debug "Sierra base info"
    #Name（名称）
    at_command="AT+CGMM"
    name=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p' | sed 's/\r//g')
    #Manufacturer（制造商）
    at_command="AT+CGMI"
    manufacturer=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p' | sed 's/\r//g')
    #Revision（固件版本）
    at_command="ATI"
    revision=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "Revision:" | sed 's/Revision: //g' | sed 's/\r//g')
    # at_command="AT+CGMR"
    # revision=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p' | sed 's/\r//g')

    #Mode（拨号模式）
    mode=$(sierra_get_mode ${at_port} ${platform} | tr 'a-z' 'A-Z')

    #Temperature（温度）
    temperature=$(sierra_get_temperature ${at_port})
}




#获取SIM卡状态
# $1:SIM卡状态标志
sierra_get_sim_status()
{
    local sim_status
    case $1 in
        "") sim_status="miss" ;;
        *"READY"*) sim_status="ready" ;;
        *"SIM PIN"*) sim_status="MT is waiting SIM PIN to be given" ;;
        *"SIM PUK"*) sim_status="MT is waiting SIM PUK to be given" ;;
        *"PH-FSIM PIN"*) sim_status="MT is waiting phone-to-SIM card password to be given" ;;
        *"PH-FSIM PIN"*) sim_status="MT is waiting phone-to-very first SIM card password to be given" ;;
        *"PH-FSIM PUK"*) sim_status="MT is waiting phone-to-very first SIM card unblocking password to be given" ;;
        *"SIM PIN2"*) sim_status="MT is waiting SIM PIN2 to be given" ;;
        *"SIM PUK2"*) sim_status="MT is waiting SIM PUK2 to be given" ;;
        *"PH-NET PIN"*) sim_status="MT is waiting network personalization password to be given" ;;
        *"PH-NET PUK"*) sim_status="MT is waiting network personalization unblocking password to be given" ;;
        *"PH-NETSUB PIN"*) sim_status="MT is waiting network subset personalization password to be given" ;;
        *"PH-NETSUB PUK"*) sim_status="MT is waiting network subset personalization unblocking password to be given" ;;
        *"PH-SP PIN"*) sim_status="MT is waiting service provider personalization password to be given" ;;
        *"PH-SP PUK"*) sim_status="MT is waiting service provider personalization unblocking password to be given" ;;
        *"PH-CORP PIN"*) sim_status="MT is waiting corporate personalization password to be given" ;;
        *"PH-CORP PUK"*) sim_status="MT is waiting corporate personalization unblocking password to be given" ;;
        *) sim_status="unknown" ;;
    esac
    echo "$sim_status"
}


sierra_sim_info()
{
    debug "Sierra sim info"
    
    #SIM Slot（SIM卡卡槽）
    #at_command="AT+QUIMSLOT?"
	#sim_slot=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+QUIMSLOT:" | awk -F' ' '{print $2}' | sed 's/\r//g')

    #IMEI（国际移动设备识别码）
    at_command="AT+CGSN"
	imei=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p' | sed 's/\r//g')

    #SIM Status（SIM状态）
    at_command="AT+CPIN?"
	sim_status_flag=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p')
    sim_status=$(sierra_get_sim_status "$sim_status_flag")

    if [ "$sim_status" != "ready" ]; then
        return
    fi

    #ISP（互联网服务提供商）
    at_command="AT+COPS?"
    isp=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p' | awk -F'"' '{print $2}')
    # if [ "$isp" = "CHN-CMCC" ] || [ "$isp" = "CMCC" ]|| [ "$isp" = "46000" ]; then
    #     isp="中国移动"
    # # elif [ "$isp" = "CHN-UNICOM" ] || [ "$isp" = "UNICOM" ] || [ "$isp" = "46001" ]; then
    # elif [ "$isp" = "CHN-UNICOM" ] || [ "$isp" = "CUCC" ] || [ "$isp" = "46001" ]; then
    #     isp="中国联通"
    # # elif [ "$isp" = "CHN-CT" ] || [ "$isp" = "CT" ] || [ "$isp" = "46011" ]; then
    # elif [ "$isp" = "CHN-TELECOM" ] || [ "$isp" = "CTCC" ] || [ "$isp" = "46011" ]; then
    #     isp="中国电信"
    # fi

    #SIM Number（SIM卡号码，手机号）
    at_command="AT+CNUM"
	sim_number=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p' | awk -F'"' '{print $4}')

    #IMSI（国际移动用户识别码）
    at_command="AT+CIMI"
	imsi=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | sed -n '2p' | sed 's/\r//g')

    #ICCID（集成电路卡识别码）
    at_command="AT+ICCID"
	# iccid=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep -o "+ICCID:[ ]*[-0-9]\+" | grep -o "[-0-9]\{1,4\}")
}

#获取网络类型
# $1:网络类型数字
sierra_get_rat()
{
    local rat
    case $1 in
		"0"|"1"|"3"|"8") rat="GSM" ;;
		"2"|"4"|"5"|"6"|"9"|"10") rat="WCDMA" ;;
        "7") rat="LTE" ;;
        "11"|"12"|"13") rat="NR" ;;
	esac
    echo "${rat}"
}


#获取信号强度指示
# $1:信号强度指示数字
sierra_get_rssi()
{
    local rssi
    case $1 in
		"99") rssi="unknown" ;;
		* )  rssi=$((2 * $1 - 113)) ;;
	esac
    echo "$rssi"
}


#网络信息
sierra_network_info()
{
    debug "Sierra network info"

    #Connect Status（连接状态）
    connect_status=$(sierra_get_connect_status ${at_port} ${define_connect})
    if [ "$connect_status" != "connect" ]; then
        return
    fi

    #Network Type（网络类型）
    at_command="AT!GSTATUS?"
    network_type=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "^System" | awk '{print $3}')

    [ -z "$network_type" ] && {
        at_command='AT+COPS?'
        local rat_num=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+COPS:" | awk -F',' '{print $4}' | sed 's/\r//g')
        network_type=$(sierra_get_rat ${rat_num})
    }

    #CSQ（信号强度）
    at_command="AT+CSQ"
    response=$(sh ${SCRIPT_DIR}/modem_at.sh ${at_port} ${at_command} | grep "+CSQ:" | sed 's/+CSQ: //g' | sed 's/\r//g')

    #RSSI（信号强度指示）
    # rssi_num=$(echo $response | awk -F',' '{print $1}')
    # rssi=$(quectel_get_rssi $rssi_num)
    #Ber（信道误码率）
    # ber=$(echo $response | awk -F',' '{print $2}')

    #PER（信号强度）
    # if [ -n "$csq" ]; then
    #     per=$((csq * 100/31))"%"
    # fi

    #最大比特率，信道质量指示
    #at_command='AT+QNWCFG="nr5g_ambr"'
    #response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+QNWCFG:")
    #for context in $response; do
    #    local apn=$(echo "$context" | awk -F'"' '{print $4}' | tr 'a-z' 'A-Z')
    #    if [ -n "$apn" ] && [ "$apn" != "IMS" ]; then
    #       cqi_ul=$(echo "$context" | awk -F',' '{print $5}')
    #    ambr_ul=$(echo "$context" | awk -F',' '{print $6}' | sed 's/\r//g')
    #        #AMBR DL（下行签约速率，单位，Mbps）
    #        ambr_dl=$(echo "$context" | awk -F',' '{print $4}')
    #        break
    #    fi
    #done

    #速率统计
    #at_command='AT+QNWCFG="up/down"'
    #response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command | grep "+QNWCFG:" | sed 's/+QNWCFG: "up\/down",//g' | sed 's/\r//g')

    #当前上传速率（单位，Byte/s）
    #tx_rate=$(echo $response | awk -F',' '{print $1}')

    #当前下载速率（单位，Byte/s）
    #rx_rate=$(echo $response | awk -F',' '{print $2}')
}


sierra_get_band()
{
    local band
    case $1 in
        "WCDMA") band="$2" ;;
        "LTE") band="$2" ;;
        "NR") band="$2" ;;
	esac
    echo "$band"
}

sierra_get_bandwidth()
{
    local network_type="$1"
    local bandwidth_num="$2"

    local bandwidth
    case $network_type in
		"LTE")
            case $bandwidth_num in
                "0") bandwidth="1.4" ;;
                "1") bandwidth="3" ;;
                "2"|"3"|"4"|"5") bandwidth=$((($bandwidth_num - 1) * 5)) ;;
            esac
        ;;
        "NR")
            case $bandwidth_num in
                "0"|"1"|"2"|"3"|"4"|"5") bandwidth=$((($bandwidth_num + 1) * 5)) ;;
                "6"|"7"|"8"|"9"|"10"|"11"|"12") bandwidth=$((($bandwidth_num - 2) * 10)) ;;
                "13") bandwidth="200" ;;
                "14") bandwidth="400" ;;
            esac
        ;;
	esac
    echo "$bandwidth"
}

sierra_get_scs()
{
    local scs
	case $1 in
		"0") scs="15" ;;
		"1") scs="30" ;;
        "2") scs="60" ;;
        "3") scs="120" ;;
        "4") scs="240" ;;
        *) scs=$(awk "BEGIN{ print 2^$1 * 15 }") ;;
	esac
    echo "$scs"
}

# WCDMA chua sua
sierra_get_phych()
{
    local phych
	case $1 in
		"0") phych="DPCH" ;;
        "1") phych="FDPCH" ;;
	esac
    echo "$phych"
}

#获取扩频因子
# $1:扩频因子数字
sierra_get_sf()
{
    local sf
	case $1 in
		"0"|"1"|"2"|"3"|"4"|"5"|"6"|"7") sf=$(awk "BEGIN{ print 2^$(($1+2)) }") ;;
        "8") sf="UNKNOWN" ;;
	esac
    echo "$sf"
}

sierra_get_slot()
{
    local slot=$1
	# case $1 in
		# "0"|"1"|"2"|"3"|"4"|"5"|"6"|"7"|"8"|"9"|"10"|"11"|"12"|"13"|"14"|"15"|"16") slot=$1 ;;
        # "0"|"1"|"2"|"3"|"4"|"5"|"6"|"7"|"8"|"9") slot=$1 ;;
	# esac
    echo "$slot"
}

#小区信息
sierra_cell_info()
{
    debug "Sierra cell info"

    local at_command='AT!GSTATUS?'
    response=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command)

    local lte=$(echo "$response" | grep "System mode:" | grep -o "LTE")
    local nr5g_nsa=$(echo "$response" | grep "System mode:" | grep -o "ENDC")

    local at_command='AT!LTEINFO?'
    lte_info=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command)

    local at_command='AT!NRINFO?'
    nr_info=$(sh ${SCRIPT_DIR}/modem_at.sh $at_port $at_command)
    if [ -n "$nr5g_nsa" ] ; then
        #EN-DC模式
        network_mode="EN-DC Mode"
        # Parse LTE parameters
        endc_lte_mcc=$(echo "$lte_info" | grep -A1 "Serving:" | tail -1 | awk '{print $2}')
        endc_lte_mnc=$(echo "$lte_info" | grep -A1 "Serving:" | tail -1 | awk '{print $3}')
        endc_lte_physical_cell_id=$(echo "$lte_info" | grep -A1 "Serving:" | tail -1 | awk '{print $10}')
        endc_lte_cell_id=$(echo "$response" | grep "Cell ID:" | awk '{print $6}')
        endc_lte_freq_band_ind=$(echo "$response" | grep "LTE band:" | awk '{ print $3}')
        #ul_bandwidth_num=$(echo "$response" | grep "LTE Tx chan:" | awk '{print $8}')
        #endc_lte_ul_bandwidth=$(sierra_get_bandwidth "LTE" $ul_bandwidth_num)
        #dl_bandwidth_num=$(echo "$response" | grep "LTE Rx chan:" | awk '{print $4}')
        endc_lte_dl_bandwidth=$(echo "$response" | grep "LTE bw:" | awk '{ print $6}')
        endc_lte_tac=$(echo "$response" | grep "TAC:" | awk '{ print $7}' | tr -d '()')
        endc_lte_earfcn=$(echo "$response" | grep "LTE Rx chan:" | awk '{print $4}')
        endc_lte_rsrp=$(echo "$response" | grep "PCC Rx0 RSRP:" | awk '{print $8}')
        endc_lte_rsrq=$(echo "$lte_info" | grep -A1 "Serving:" | tail -1 | awk '{print $11}')
        endc_lte_sinr=$(echo "$lte_info" | grep -A1 "Serving:" | tail -1 | awk '{print $9}')

        # Extract all CA SCell parameters from the data line --> CHUA SUA
        ca_scell_line=$(echo "$lte_info" | sed -n '/CA SCell :/,/WCDMA:/p' | grep -E '^\s+[0-9]+\s')
        ca_scell_earfcn=$(echo "$ca_scell_line" | awk '{print $1}')    # 550
        ca_scell_scid=$(echo "$ca_scell_line" | awk '{print $2}')      # 1
        ca_scell_bd=$(echo "$ca_scell_line" | awk '{print $3}')        # 1
        ca_scell_st=$(echo "$ca_scell_line" | awk '{print $4}')        # 1
        ca_scell_d=$(echo "$ca_scell_line" | awk '{print $5}')         # 3
        ca_scell_u=$(echo "$ca_scell_line" | awk '{print $6}')         # 0
        ca_scell_mdl=$(echo "$ca_scell_line" | awk '{print $7}')       # 1
        ca_scell_mul=$(echo "$ca_scell_line" | awk '{print $8}')       # 0
        ca_scell_pci=$(echo "$ca_scell_line" | awk '{print $9}')       # 3
        ca_scell_rsrp=$(echo "$ca_scell_line" | awk '{print $10}')     # -85.8
        ca_scell_rssi=$(echo "$ca_scell_line" | awk '{print $11}')     # -53.3
        ca_scell_sinr=$(echo "$ca_scell_line" | awk '{print $12}')     # 5

        # Parse 5G-NSA parameters
        #endc_nr_physical_cell_id=$(echo "$nr_info" | grep "NR5G Cell ID:" | awk '{print $4}')
        endc_nr_band=$(echo "$nr_info" | grep "NR5G band:" | awk '{print $3}'| sed 's/n//')
        endc_nr_bw=$(echo "$nr_info" | grep "NR5G dl bw:" | awk '{print $4}')
        endc_nr_rsrp=$(echo "$nr_info" | grep "NR5G RSRP (dBm):" | awk '{print $4}')
        endc_nr_rsrq=$(echo "$nr_info" | grep "NR5G RSRQ (dB):" | awk '{print $8}')
        endc_nr_sinr=$(echo "$nr_info" | grep "NR5G SINR (dB):" | awk '{print $4}')
        endc_nr_arfcn=$(echo "$nr_info" | grep "NR5G Rx chan:" | awk '{print $4}')


    else
        #SA，LTE，WCDMA模式
        response=$(echo "$response" | grep "System mode:")
        local rat=$(echo "$response" | awk '{print $3}')
        case $rat in
            "SA")
                network_mode="NR5G-SA Mode"
                nr_duplex_mode=$(echo "$response" | awk -F',' '{print $4}' | sed 's/"//g')
                nr_mcc=$(echo "$response" | awk -F',' '{print $5}')
                nr_mnc=$(echo "$response" | awk -F',' '{print $6}')
                nr_cell_id=$(echo "$response" | awk -F',' '{print $7}')
                nr_physical_cell_id=$(echo "$response" | awk -F',' '{print $8}')
                nr_tac=$(echo "$response" | awk -F',' '{print $9}')
                nr_arfcn=$(echo "$response" | awk -F',' '{print $10}')
                nr_band_num=$(echo "$response" | awk -F',' '{print $11}')
                nr_band=$(quectel_get_band "NR" $nr_band_num)
                nr_dl_bandwidth_num=$(echo "$response" | awk -F',' '{print $12}')
                nr_dl_bandwidth=$(quectel_get_bandwidth "NR" $nr_dl_bandwidth_num)
                nr_rsrp=$(echo "$response" | awk -F',' '{print $13}')
                nr_rsrq=$(echo "$response" | awk -F',' '{print $14}')
                nr_sinr=$(echo "$response" | awk -F',' '{print $15}')
                nr_scs_num=$(echo "$response" | awk -F',' '{print $16}')
                nr_scs=$(quectel_get_scs $nr_scs_num)
                nr_srxlev=$(echo "$response" | awk -F',' '{print $17}' | sed 's/\r//g')
            ;;
            "LTE"|"CAT-M"|"CAT-NB")
                network_mode="LTE Mode"
                lte_mcc=$(echo "$lte_info" | grep -A1 "Serving:" | tail -1 | awk '{print $2}')
                lte_mnc=$(echo "$lte_info" | grep -A1 "Serving:" | tail -1 | awk '{print $3}')
                lte_physical_cell_id=$(echo "$lte_info" | grep -A1 "Serving:" | tail -1 | awk '{print $10}')
                lte_cell_id=$(echo "$lte_info" | grep "Cell ID:" | awk '{print $6}')
                lte_freq_band_ind=$(echo "$response" | grep "LTE band:" | awk '{ print $3}')
                #ul_bandwidth_num=$(echo "$response" | grep "LTE Tx chan:" | awk '{print $8}')
                #endc_lte_ul_bandwidth=$(sierra_get_bandwidth "LTE" $ul_bandwidth_num)
                #dl_bandwidth_num=$(echo "$response" | grep "LTE Rx chan:" | awk '{print $4}')
                lte_dl_bandwidth=$(echo "$response" | grep "LTE bw:" | awk '{ print $6}')
                lte_tac=$(echo "$response" | grep "TAC:" | awk '{ print $7}' | tr -d '()')
                lte_earfcn=$(echo "$response" | grep "LTE Rx chan:" | awk '{print $4}')
                lte_rsrp=$(echo "$response" | grep "PCC Rx0 RSRP:" | awk '{print $3}')
                lte_rsrq=$(echo "$response" | grep "RSRQ (dB):" | awk '{print $3}')
                lte_sinr=$(echo "$response" | grep "SINR (dB):" | awk '{print $3}')
            ;;
            "WCDMA")
                network_mode="WCDMA Mode"
                wcdma_mcc=$(echo "$response" | awk -F',' '{print $4}')
                wcdma_mnc=$(echo "$response" | awk -F',' '{print $5}')
                wcdma_lac=$(echo "$response" | awk -F',' '{print $6}')
                wcdma_cell_id=$(echo "$response" | awk -F',' '{print $7}')
                wcdma_uarfcn=$(echo "$response" | awk -F',' '{print $8}')
                wcdma_psc=$(echo "$response" | awk -F',' '{print $9}')
                wcdma_rac=$(echo "$response" | awk -F',' '{print $10}')
                wcdma_rscp=$(echo "$response" | awk -F',' '{print $11}')
                wcdma_ecio=$(echo "$response" | awk -F',' '{print $12}')
                wcdma_phych_num=$(echo "$response" | awk -F',' '{print $13}')
                wcdma_phych=$(quectel_get_phych $wcdma_phych_num)
                wcdma_sf_num=$(echo "$response" | awk -F',' '{print $14}')
                wcdma_sf=$(quectel_get_sf $wcdma_sf_num)
                wcdma_slot_num=$(echo "$response" | awk -F',' '{print $15}')
                wcdma_slot=$(quectel_get_slot $wcdma_slot_num)
                wcdma_speech_code=$(echo "$response" | awk -F',' '{print $16}')
                wcdma_com_mod=$(echo "$response" | awk -F',' '{print $17}' | sed 's/\r//g')
            ;;
        esac
    fi

    return

}


get_sierra_info()
{
    debug "get sierra info"
    #设置AT串口
    at_port="$1"
    platform="$2"
    define_connect="$3"

    #基本信息
    sierra_base_info

	#SIM卡信息
    sierra_sim_info
    if [ "$sim_status" != "ready" ]; then
        return
    fi

    #网络信息
    sierra_network_info
    if [ "$connect_status" != "connect" ]; then
        return
    fi

    #小区信息
    sierra_cell_info

    return

}


