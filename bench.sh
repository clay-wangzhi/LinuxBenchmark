#!/usr/bin/env bash
#
# Description: Auto test bench

trap _exit INT QUIT TERM

_red() {
    printf '\033[0;31;31m%b\033[0m' "$1"
}

_green() {
    printf '\033[0;31;32m%b\033[0m' "$1"
}

_yellow() {
    printf '\033[0;31;33m%b\033[0m' "$1"
}

_blue() {
    printf '\033[0;31;36m%b\033[0m' "$1"
}

_exists() {
    local cmd="$1"
    if eval type type > /dev/null 2>&1; then
        eval type "$cmd" > /dev/null 2>&1
    elif command > /dev/null 2>&1; then
        command -v "$cmd" > /dev/null 2>&1
    else
        which "$cmd" > /dev/null 2>&1
    fi
    local rt=$?
    return ${rt}
}

get_opsy() {
    [ -f /etc/redhat-release ] && awk '{print $0}' /etc/redhat-release && return
    [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
    [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

next() {
    printf "%-70s\n" "-" | sed 's/\s/-/g'
}

calc_size() {
    local raw=$1
    local total_size=0
    local num=1
    local unit="KB"
    if ! [[ ${raw} =~ ^[0-9]+$ ]] ; then
        echo ""
        return
    fi
    if [ "${raw}" -ge 1073741824 ]; then
        num=1073741824
        unit="TB"
    elif [ "${raw}" -ge 1048576 ]; then
        num=1048576
        unit="GB"
    elif [ "${raw}" -ge 1024 ]; then
        num=1024
        unit="MB"
    elif [ "${raw}" -eq 0 ]; then
        echo "${total_size}"
        return
    fi
    total_size=$( awk 'BEGIN{printf "%.1f", '$raw' / '$num'}' )
    echo "${total_size} ${unit}"
}

install_tools() {
    curl -fsSL "https://gitee.com/clay-wangzhi/shell/raw/master/repo_replace.sh" | bash
    yum -y install bc sysbench nginx httpd-tools mariadb-server redis gcc gcc-gfortran
    cd ./github_schbench/ && make
    cd ..
    cd ./github_stream/ && make
    cd ..
}

check_virt(){
    _exists "dmesg" && virtualx="$(dmesg 2>/dev/null)"
    if _exists "dmidecode"; then
        sys_manu="$(dmidecode -s system-manufacturer 2>/dev/null)"
        sys_product="$(dmidecode -s system-product-name 2>/dev/null)"
        sys_ver="$(dmidecode -s system-version 2>/dev/null)"
    else
        sys_manu=""
        sys_product=""
        sys_ver=""
    fi
    if   grep -qa docker /proc/1/cgroup; then
        virt="Docker"
    elif grep -qa lxc /proc/1/cgroup; then
        virt="LXC"
    elif grep -qa container=lxc /proc/1/environ; then
        virt="LXC"
    elif [[ -f /proc/user_beancounters ]]; then
        virt="OpenVZ"
    elif [[ "${virtualx}" == *kvm-clock* ]]; then
        virt="KVM"
    elif [[ "${sys_product}" == *KVM* ]]; then
        virt="KVM"
    elif [[ "${cname}" == *KVM* ]]; then
        virt="KVM"
    elif [[ "${cname}" == *QEMU* ]]; then
        virt="KVM"
    elif [[ "${virtualx}" == *"VMware Virtual Platform"* ]]; then
        virt="VMware"
    elif [[ "${virtualx}" == *"Parallels Software International"* ]]; then
        virt="Parallels"
    elif [[ "${virtualx}" == *VirtualBox* ]]; then
        virt="VirtualBox"
    elif [[ -e /proc/xen ]]; then
        if grep -q "control_d" "/proc/xen/capabilities" 2>/dev/null; then
            virt="Xen-Dom0"
        else
            virt="Xen-DomU"
        fi
    elif [ -f "/sys/hypervisor/type" ] && grep -q "xen" "/sys/hypervisor/type"; then
        virt="Xen"
    elif [[ "${sys_manu}" == *"Microsoft Corporation"* ]]; then
        if [[ "${sys_product}" == *"Virtual Machine"* ]]; then
            if [[ "${sys_ver}" == *"7.0"* || "${sys_ver}" == *"Hyper-V" ]]; then
                virt="Hyper-V"
            else
                virt="Microsoft Virtual Machine"
            fi
        fi
    else
        virt="Dedicated"
    fi
}

# Get System information
get_system_info() {
    cname=$( awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' )
    cores=$( awk -F: '/processor/ {core++} END {print core}' /proc/cpuinfo )
    freq=$( awk -F'[ :]' '/cpu MHz/ {print $4;exit}' /proc/cpuinfo )
    ccache=$( awk -F: '/cache size/ {cache=$2} END {print cache}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' )
    cpu_aes=$( grep -i 'aes' /proc/cpuinfo )
    cpu_virt=$( grep -Ei 'vmx|svm' /proc/cpuinfo )
    tram=$( LANG=C; free | awk '/Mem/ {print $2}' )
    tram=$( calc_size $tram )
    uram=$( LANG=C; free | awk '/Mem/ {print $3}' )
    uram=$( calc_size $uram )
    swap=$( LANG=C; free | awk '/Swap/ {print $2}' )
    swap=$( calc_size $swap )
    uswap=$( LANG=C; free | awk '/Swap/ {print $3}' )
    uswap=$( calc_size $uswap )
    up=$( awk '{a=$1/86400;b=($1%86400)/3600;c=($1%3600)/60} {printf("%d days, %d hour %d min\n",a,b,c)}' /proc/uptime )
    if _exists "w"; then
        load=$( LANG=C; w | head -1 | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//' )
    elif _exists "uptime"; then
        load=$( LANG=C; uptime | head -1 | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//' )
    fi
    opsy=$( get_opsy )
    arch=$( uname -m )
    if _exists "getconf"; then
        lbit=$( getconf LONG_BIT )
    else
        echo ${arch} | grep -q "64" && lbit="64" || lbit="32"
    fi
    kern=$( uname -r )
    disk_total_size=$( LANG=C; df -t simfs -t ext2 -t ext3 -t ext4 -t btrfs -t xfs -t vfat -t ntfs -t swap --total 2>/dev/null | grep total | awk '{ print $2 }' )
    disk_total_size=$( calc_size $disk_total_size )
    disk_used_size=$( LANG=C; df -t simfs -t ext2 -t ext3 -t ext4 -t btrfs -t xfs -t vfat -t ntfs -t swap --total 2>/dev/null | grep total | awk '{ print $3 }' )
    disk_used_size=$( calc_size $disk_used_size )
    tcpctrl=$( sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}' )
}

cpu_super_pi_test() {
    time echo "scale=5000; 4*a(1)" | bc -l -q &>1
}

cpu_schbench_test() {
    ./github_schbench/schbench -m 1 -t $1
}
cpu_sysbench_test() {
    sysbench --threads=$1 --events=10000 --time=0 cpu run | awk  '/total time/{print $3}' | sed '$s/.$//'
}

memory_stream_test() {
    ./github_stream/stream_c.exe
}

memroy_mlc_test() {
    ./mlc --latency_matrix
}

memory_sysbench_test() {
    sysbench memory --threads=4 --memory-block-size=8K --memory-total-size=100G --memory-oper=$1 --memory-access-mode=$2 run | awk -F'[ (]' '/transferred/{print $5}'
}

io_test() {
    (LANG=C dd if=/dev/zero of=benchtest_$$ bs=512k count=$1 conv=fdatasync && rm -f benchtest_$$ ) 2>&1 | awk -F, '{io=$NF} END { print io}' | sed 's/^[ \t]*//;s/[ \t]*$//'
}

# Print System information
print_system_info() {
    echo "---------------------------- system info -----------------------------"
    if [ -n "$cname" ]; then
        echo " CPU Model          : $(_blue "$cname")"
    else
        echo " CPU Model          : $(_blue "CPU model not detected")"
    fi
    if [ -n "$freq" ]; then
        echo " CPU Cores          : $(_blue "$cores @ $freq MHz")"
    else
        echo " CPU Cores          : $(_blue "$cores")"
    fi
    if [ -n "$ccache" ]; then
        echo " CPU Cache          : $(_blue "$ccache")"
    fi
    if [ -n "$cpu_aes" ]; then
        echo " AES-NI             : $(_green "Enabled")"
    else
        echo " AES-NI             : $(_red "Disabled")"
    fi
    if [ -n "$cpu_virt" ]; then
        echo " VM-x/AMD-V         : $(_green "Enabled")"
    else
        echo " VM-x/AMD-V         : $(_red "Disabled")"
    fi
    echo " Total Disk         : $(_yellow "$disk_total_size") $(_blue "($disk_used_size Used)")"
    echo " Total Mem          : $(_yellow "$tram") $(_blue "($uram Used)")"
    if [ "$swap" != "0" ]; then
        echo " Total Swap         : $(_blue "$swap ($uswap Used)")"
    fi
    echo " System uptime      : $(_blue "$up")"
    echo " Load average       : $(_blue "$load")"
    echo " OS                 : $(_blue "$opsy")"
    echo " Arch               : $(_blue "$arch ($lbit Bit)")"
    echo " Kernel             : $(_blue "$kern")"
    echo " TCP CC             : $(_yellow "$tcpctrl")"
    echo " Virtualization     : $(_blue "$virt")"
}

print_cpu_test() {
    echo "------------------------------ cpu test ------------------------------"
    # 循环三次，求平均值
    for _ in $(seq 1 3); do
        # 1、2、4 线程分别测试
        for thread in 1 2 4; do
            for i in $(seq 1 $thread); do
                ( cpu_super_pi_test )  2>time${thread}${i}.txt &
            done
            wait
            grep real time${thread}*.txt | awk '{print $2}' | awk -F[ms] '{S+=($1 * 60) + $2} END{print S/NR}' >> res${thread}.txt
        done
        # 避免持续高负载影响数据准确性
        sleep 30
    done
    cpu1=$(awk '{S+=$1}END{printf "%.3f\n",S/NR}' res1.txt)
    cpu2=$(awk '{S+=$1}END{printf "%.3f\n",S/NR}' res2.txt)
    cpu4=$(awk '{S+=$1}END{printf "%.3f\n",S/NR}' res4.txt)
    echo "Super_Pi 单核计算耗时：$(_blue "$cpu1"秒)"
    echo "Super_Pi 2核计算耗时：$(_blue "$cpu2"秒)"
    echo "Super_Pi 4核计算耗时：$(_blue "$cpu4"秒)"
    rm -f res*.txt time*.txt

    for _ in $(seq 1 3); do
        for thread in 1 2 4; do
            ( cpu_schbench_test $thread) 2> sch${thread}.txt
            grep 99.0th sch${thread}.txt | tail -1 | awk '{print $3}' >> res${thread}.txt
        done
        sleep 30
    done
    cpu1=$(awk '{S+=$1}END{printf "%.1f\n",S/NR}' res1.txt)
    cpu2=$(awk '{S+=$1}END{printf "%.1f\n",S/NR}' res2.txt)
    cpu4=$(awk '{S+=$1}END{printf "%.1f\n",S/NR}' res4.txt)
    echo "CPU调度延时 单线程：$(_blue "$cpu1"微秒)"
    echo "CPU调度延时 2线程：$(_blue "$cpu2"微秒)"
    echo "CPU调度延时 4线程：$(_blue "$cpu4"微秒)"
    rm -f res*.txt sch*.txt

    for _ in $(seq 1 3); do
        for thread in 1 2 4; do
            cpu_sysbench_test $thread >> cpu_sysbench$thread.txt
        done
        sleep 10
    done
    cpu1=$(awk '{S+=$1}END{printf "%.3f\n",S/NR}' cpu_sysbench1.txt)
    cpu2=$(awk '{S+=$1}END{printf "%.3f\n",S/NR}' cpu_sysbench2.txt)
    cpu4=$(awk '{S+=$1}END{printf "%.3f\n",S/NR}' cpu_sysbench4.txt)
    echo "sysbench 素数计算 单线程：$(_blue "$cpu1"秒)"
    echo "sysbench 素数计算 2线程：$(_blue "$cpu2"秒)"
    echo "sysbench 素数计算 4线程：$(_blue "$cpu4"秒)"
    rm -f cpu_sysbench*.txt
}

print_memory_test() {
    echo "---------------------------- memory test -----------------------------"
    for _ in $(seq 1 3); do
        for thread in 1 2 4; do
            OMP_NUM_THREADS=${thread} memory_stream_test > stream${thread}.txt
            grep Copy stream${thread}.txt  | awk '{print $2/1024}' >> res_copy${thread}.txt
            grep Scale stream${thread}.txt  | awk '{print $2/1024}' >> res_scale${thread}.txt
            grep Add stream${thread}.txt  | awk '{print $2/1024}' >> res_add${thread}.txt
            grep Triad stream${thread}.txt  | awk '{print $2/1024}' >> res_triad${thread}.txt
        done
    done
    memory_copy1=$(awk '{S+=$1}END{printf "%.1f\n",S/NR}' res_copy1.txt)
    memory_scale1=$(awk '{S+=$1}END{printf "%.1f\n",S/NR}' res_scale1.txt)
    memory_add1=$(awk '{S+=$1}END{printf "%.1f\n",S/NR}' res_add1.txt)
    memory_triad1=$(awk '{S+=$1}END{printf "%.1f\n",S/NR}' res_triad1.txt)

    memory_copy2=$(awk '{S+=$1}END{printf "%.1f\n",S/NR}' res_copy2.txt)
    memory_scale2=$(awk '{S+=$1}END{printf "%.1f\n",S/NR}' res_scale2.txt)
    memory_add2=$(awk '{S+=$1}END{printf "%.1f\n",S/NR}' res_add2.txt)
    memory_triad2=$(awk '{S+=$1}END{printf "%.1f\n",S/NR}' res_triad2.txt)

    memory_copy4=$(awk '{S+=$1}END{printf "%.1f\n",S/NR}' res_copy4.txt)
    memory_scale4=$(awk '{S+=$1}END{printf "%.1f\n",S/NR}' res_scale4.txt)
    memory_add4=$(awk '{S+=$1}END{printf "%.1f\n",S/NR}' res_add4.txt)
    memory_triad4=$(awk '{S+=$1}END{printf "%.1f\n",S/NR}' res_triad4.txt)

    echo "内存带宽 单线程 Copy：$(_blue "$memory_copy1"GB/s)"
    echo "内存带宽 单线程 Scale：$(_blue "$memory_scale1"GB/s)"
    echo "内存带宽 单线程 Add：$(_blue "$memory_add1"GB/s)"
    echo "内存带宽 单线程 Triad：$(_blue "$memory_triad1"GB/s)"

    echo "内存带宽 2线程 Copy：$(_blue "$memory_copy2"GB/s)"
    echo "内存带宽 2线程 Scale：$(_blue "$memory_scale2"GB/s)"
    echo "内存带宽 2线程 Add：$(_blue "$memory_add2"GB/s)"
    echo "内存带宽 2线程 Triad：$(_blue "$memory_triad2"GB/s)"

    echo "内存带宽 4线程 Copy：$(_blue "$memory_copy4"GB/s)"
    echo "内存带宽 4线程 Scale：$(_blue "$memory_scale4"GB/s)"
    echo "内存带宽 4线程 Add：$(_blue "$memory_add4"GB/s)"
    echo "内存带宽 4线程 Triad：$(_blue "$memory_triad4"GB/s)"
    rm -f res*.txt stream*.txt

    for _ in $(seq 1 3); do
        memroy_mlc_test | tail -1 | awk '{print $2}' >> res_mlc.txt
    done
    memory_mlc_avg=$(awk '{S+=$1}END{printf "%.1f\n",S/NR}' res_mlc.txt)
    echo "内存时延：$(_blue "$memory_mlc_avg"纳秒)"
    rm -f res_mlc.txt

    for _ in $(seq 1 3); do
        for oper in write read; do
            for mode in seq rnd; do
                memory_sysbench_test $oper $mode >> memory_${oper}_${mode}.txt
            done
        done
    done
    memory_write_seq=$(awk '{S+=$1}END{printf "%.2f\n",S/NR}' memory_write_seq.txt)
    memory_read_seq=$(awk '{S+=$1}END{printf "%.2f\n",S/NR}' memory_read_seq.txt)
    memory_write_rnd=$(awk '{S+=$1}END{printf "%.2f\n",S/NR}' memory_write_rnd.txt)
    memory_read_rnd=$(awk '{S+=$1}END{printf "%.2f\n",S/NR}' memory_read_rnd.txt)
    echo "sysbench 顺序写：$(_blue "$memory_write_seq"MiB/sec)"
    echo "sysbench 顺序读：$(_blue "$memory_read_seq"MiB/sec)"
    echo "sysbench 随机写：$(_blue "$memory_write_rnd"MiB/sec)"
    echo "sysbench 随机写：$(_blue "$memory_read_rnd"MiB/sec)"
    rm -f memory*.txt
}

print_io_test() {
    echo "------------------------------ io test -------------------------------"
    freespace=$( df -m . | awk 'NR==2 {print $4}' )
    if [ -z "${freespace}" ]; then
        freespace=$( df -m . | awk 'NR==3 {print $3}' )
    fi
    if [ ${freespace} -gt 1024 ]; then
        writemb=2048
        io1=$( io_test ${writemb} )
        # echo " I/O Speed(1st run) : $(_blue "$io1")"
        io2=$( io_test ${writemb} )
        # echo " I/O Speed(2nd run) : $(_blue "$io2")"
        io3=$( io_test ${writemb} )
        # echo " I/O Speed(3rd run) : $(_blue "$io3")"
        ioraw1=$( echo $io1 | awk 'NR==1 {print $1}' )
        [ "`echo $io1 | awk 'NR==1 {print $2}'`" == "GB/s" ] && ioraw1=$( awk 'BEGIN{print '$ioraw1' * 1024}' )
        ioraw2=$( echo $io2 | awk 'NR==1 {print $1}' )
        [ "`echo $io2 | awk 'NR==1 {print $2}'`" == "GB/s" ] && ioraw2=$( awk 'BEGIN{print '$ioraw2' * 1024}' )
        ioraw3=$( echo $io3 | awk 'NR==1 {print $1}' )
        [ "`echo $io3 | awk 'NR==1 {print $2}'`" == "GB/s" ] && ioraw3=$( awk 'BEGIN{print '$ioraw3' * 1024}' )
        ioall=$( awk 'BEGIN{print '$ioraw1' + '$ioraw2' + '$ioraw3'}' )
        ioavg=$( awk 'BEGIN{printf "%.1f", '$ioall' / 3}' )
        echo " I/O Speed(average) : $(_blue "$ioavg MB/s")"
    else
        echo " $(_red "Not enough space for I/O Speed test!")"
    fi
}

print_nginx_test() {
    echo "----------------------------- nginx test -----------------------------"
    systemctl start nginx
    for _ in $(seq 1 3); do
        ab -c 400 -n 1000000 http://127.0.0.1/index.html 2>/dev/null | grep "Requests per second" | awk '{print $4}' >> res_nginx_short.txt
        sleep 10
        ab -c 400 -n 1000000 -k http://127.0.0.1/index.html 2>/dev/null | grep "Requests per second" | awk '{print $4}' >> res_nginx_long.txt
        sleep 10
    done
    nginx_short_avg=$(awk '{S+=$1}END{printf "%.2f\n",S/NR/10000}' res_nginx_short.txt)
    nginx_long_avg=$(awk '{S+=$1}END{printf "%.2f\n",S/NR/10000}' res_nginx_long.txt)
    echo "Nginx 短连接 QPS：$(_blue "$nginx_short_avg"万)"
    echo "Nginx 长连接 QPS：$(_blue "$nginx_long_avg"万)"
    rm -f res_nginx*.txt
}

print_mysql_test() {
    echo "----------------------------- mysql test -----------------------------"
    systemctl start mariadb
    mysql -e "create database pressure" 2>/dev/null && \
      mysql -e "grant all on pressure.* to 'pressure'@'127.0.0.1' identified by 'pressure'" && \
      sysbench --db-driver=mysql --time=300 --threads=10 --report-interval=1 --mysql-host=127.0.0.1 --mysql-port=3306 --mysql-user=pressure --mysql-password=pressure --mysql-db=pressure --tables=20 --table_size=1000000 oltp_read_write --db-ps-mode=disable prepare &>/dev/null
    for _ in $(seq 1 3); do
        sysbench --db-driver=mysql --time=300 --threads=10 --report-interval=1 --mysql-host=127.0.0.1 --mysql-port=3306 --mysql-user=pressure --mysql-password=pressure --mysql-db=pressure --tables=20 --table_size=1000000 oltp_read_write --db-ps-mode=disable run > res_mysql.txt
        awk '/read:/{print $2}' res_mysql.txt >> res_mysql_read.txt
        awk '/write:/{print $2}' res_mysql.txt >> res_mysql_write.txt
        sleep 20
    done
    mysql_read_avg=$(awk '{S+=$1}END{printf "%.2f\n",S/NR/10000}' res_mysql_read.txt)
    mysql_write_avg=$(awk '{S+=$1}END{printf "%.2f\n",S/NR/10000}' res_mysql_write.txt)
    echo "MySQL 读：$(_blue "$mysql_read_avg"万/300秒)"
    echo "MySQL 写：$(_blue "$mysql_write_avg"万/300秒)"
    rm -f res_mysql*.txt
}

print_redis_test() {
    echo "----------------------------- redis test -----------------------------"
    systemctl start redis
    for _ in $(seq 1 3); do
        redis-benchmark -t set,get -n 1000000 | grep "requests per second" | awk '{print $1}' > res_redis.txt
        head -1 res_redis.txt >> res_redis_set.txt
        tail -1 res_redis.txt >> res_redis_get.txt
    done
    redis_set_avg=$(awk '{S+=$1}END{printf "%.2f\n",S/NR/10000}' res_redis_set.txt)
    redis_get_avg=$(awk '{S+=$1}END{printf "%.2f\n",S/NR/10000}' res_redis_get.txt)
    echo "Redis Set：$(_blue "$redis_set_avg"万/秒)"
    echo "MySQL Get：$(_blue "$redis_get_avg"万/秒)"
    rm -f res_redis*.txt
}

print_end_time() {
    end_time=$(date +%s)
    time=$(( ${end_time} - ${start_time} ))
    if [ ${time} -gt 60 ]; then
        min=$(expr $time / 60)
        sec=$(expr $time % 60)
        echo " Finished in        : ${min} min ${sec} sec"
    else
        echo " Finished in        : ${time} sec"
    fi
    date_time=$(date '+%Y-%m-%d %H:%M:%S %Z')
    echo " Timestamp          : $date_time"
}

main() {
    start_time=$(date +%s)
    install_tools
    get_system_info
    check_virt
    clear
    print_system_info
    print_cpu_test
    print_memory_test
    print_io_test
    print_nginx_test
    print_mysql_test
    print_redis_test
    next
    print_end_time
}

main "$@"
