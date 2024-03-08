# Linux 性能基准测试工具及测试方法

请性能领域的大师布伦丹·格雷格（Brendan Gregg）登场 👏👏👏

![linux_benchmarking_tools](https://clay-blog.oss-cn-shanghai.aliyuncs.com/img/linux_benchmarking_tools.png)

整理测试指标如下图

 <img src="https://clay-blog.oss-cn-shanghai.aliyuncs.com/img/image-20240301222005893.png"  style="zoom: 67%;" />

> 测试环境说明： CentOS7， 4c8g

## 基础性能测试

### CPU

#### Super_Pi

**Super_Pi** 是一种用于计算圆周率π的程序，通常用于测试计算机性能和稳定性。它的主要用途是测量系统的单线程性能，因为它是一个单线程应用程序。

我们使用linux下的bc计算器程序通过反正切函数计算5000位圆周率的cpu耗时来对主机进行测试。

```bash
# 安装 bc
yum -y install bc
# 测试
time echo "scale=5000; 4*a(1)" | bc -l -q &>1
```

```bash
# 结果分析，看 real 即可，时间越短，性能越好
```

 <img src="https://clay-blog.oss-cn-shanghai.aliyuncs.com/img/image-20240301220028185.png" alt="" style="zoom:50%;" />

#### CPU 调度延时

> CPU调度延迟一般情况下，是负载的关键指标，本次压测需要空负载。当资源还没有在使用时，容器正常申请对应配置压测即可。

```bash
# 编译安装
git clone https://github.com/rgushchin/schbench.git
make
#  -t 表示线程数， -m 表示每个线程产生的信息数
./schbench -t 4 -m 1
```

####  sysbench 素数计算

```bash
# 安装 sysbench
yum -y install sysbench
# 测试方法: 启动4个线程计算10000事件所花的时间
sysbench cpu --threads=4 --events=10000 --time=0  run
```

```bash
# 结果分析，看 total time 即可，时间越短，性能越好
```

<img src="https://clay-blog.oss-cn-shanghai.aliyuncs.com/img/image-20240301173055825.png" alt="" style="zoom:50%;" /> 

### 内存

#### **内存带宽(stream)**

Stream测试是内存测试中业界公认的内存带宽性能测试基准工具

```bash
# 编译安装 STREAM
yum -y install gcc gcc-gfortran
git clone https://github.com/jeffhammond/STREAM.git
cd STREAM/
make
# 指定线程数
export OMP_NUM_THREADS=1
./stream_c.exe
```

```bash
# 结果分析，看 Copy、Scale、Add、Triad，数值越大，性能越好
```

<img src="https://clay-blog.oss-cn-shanghai.aliyuncs.com/img/image-20240301173606072.png" alt="" style="zoom:50%;" /> 

#### 内存时延(mlc)

> 官网下载：https://www.intel.com/content/www/us/en/developer/articles/tool/intelr-memory-latency-checker.html#inpage-nav-9

```bash
# 下载测试
mkdir mlc
tar -xvf mlc_v3.9a.tgz -C mlc
cd mlc/Linux/
./mlc --latency_matrix
```

#### sysbench 连续读写或者随机读写操作

```bash
# 写操作
## 线程数=4  内存块大小=8K 传输数据总量=100G 内存操作=写 内存访问模式=顺序访问
sysbench memory --threads=4 --memory-block-size=8K --memory-total-size=100G --memory-oper=write --memory-access-mode=seq run
## 线程数=4  内存块大小=8K 传输数据总量=100G 内存操作=写 内存访问模式=随机访问
sysbench memory --threads=4 --memory-block-size=8K --memory-total-size=100G --memory-oper=write --memory-access-mode=rnd run
  
# 读操作
## 线程数=4  内存块大小=8K 传输数据总量=100G 内存操作=读 内存访问模式=顺序访问
sysbench memory --threads=4 --memory-block-size=8K --memory-total-size=100G --memory-oper=read --memory-access-mode=seq run
## 线程数=4  内存块大小=8K 传输数据总量=100G 内存操作=读 内存访问模式=随机访问
sysbench memory --threads=4 --memory-block-size=8K --memory-total-size=100G --memory-oper=read --memory-access-mode=rnd run
```

### 磁盘 IO

> ⚠️  测试时请准备裸的数据盘，测试完成后请重新格式化磁盘 

测试方法和结果分析和文件 IO 测试相同，`--filename`  改为具体的数据盘即可，比如`/dev/sda `，这里不再赘述

### 文件 IO

#### FIO

**磁盘读、写iops**

iops：磁盘的每秒读写次数，这个是随机读写考察的重点

```bash
# 安装
yum -y install fio
# 测试随机读 IOPS
fio --ioengine=libaio --bs=4k --direct=1 --thread --time_based --rw=randread --filename=/home/randread.txt --runtime=60 --numjobs=1 --iodepth=1 --group_reporting --name=randread-dep1 --size=1g
# 测试随机写 IOPS
fio --ioengine=libaio --bs=4k --direct=1 --thread --time_based --rw=randwrite --filename=/home/randwrite.txt --runtime=60 --numjobs=1 --iodepth=1 --group_reporting --name=randread-dep1 --size=1g
```

```bash
# 结果分析，看 IOPS 即可，值越大，性能越好
```

 <img src="https://clay-blog.oss-cn-shanghai.aliyuncs.com/img/image-20240301175213772.png" alt="" style="zoom:50%;" />

  <img src="https://clay-blog.oss-cn-shanghai.aliyuncs.com/img/image-20240301175504178.png" alt="image-20240301175504178" style="zoom:50%;" />

**磁盘读、写带宽**

bw：磁盘的吞吐量，这个是顺序读写考察的重点

```bash
# 测试顺序读
fio --ioengine=libaio --bs=4k --direct=1 --thread --time_based --rw=read --filename=/home/read.txt --runtime=60 --numjobs=1 --iodepth=1 --group_reporting --name=randread-dep1 --size=1g
# 测试顺序写
fio --ioengine=libaio --bs=4k --direct=1 --thread --time_based --rw=write --filename=/home/write.txt --runtime=60 --numjobs=1 --iodepth=1 --group_reporting --name=randread-dep1 --size=1g
```

```bash
# 结果分析，看 BW 即可，值越大，性能越好
```

  <img src="https://clay-blog.oss-cn-shanghai.aliyuncs.com/img/image-20240301175906083.png" alt="" style="zoom:50%;" />

 <img src="https://clay-blog.oss-cn-shanghai.aliyuncs.com/img/image-20240301180201261.png" style="zoom:50%;" />

> ⚠️  **因地制宜，灵活选取。在基准测试时，一定要注意根据应用程序 I/O 的特点，来具体评估指标。**  
>
> 比如 etcd  磁盘性能衡量指标为：WAL 文件系统调用 fsync 的延迟分布，当 99% 样本的同步时间小于 10 毫秒就可以认为存储性能能够满足 etcd 的性能要求。
>
> `mkdir etcd-bench `
> `fio --rw=write --ioengine=sync --fdatasync=1 --directory=etcd-bench  --size=22m --bs=2300 --name=etcd-bench `
>
> <img src="https://clay-blog.oss-cn-shanghai.aliyuncs.com/img/image-20240301180941306.png" style="zoom:50%;" />

#### sysbench 文件随机读写速度、顺序读写吞吐率

```bash
# 线程数=4 每隔4s输出一次结果 测试时间=60s
# 文件数=2 文件总大小=4G 文件操作模式=随机读写
# 块大小 16384
sysbench --threads=4 --report-interval=4 --time=60 --test=fileio --file-num=2 --file-total-size=4G --file-test-mode=rndrw prepare
sysbench --threads=4 --report-interval=4 --time=60 --test=fileio --file-num=2 --file-total-size=4G --file-test-mode=rndrw run
sysbench --threads=4 --report-interval=4 --time=60 --test=fileio --file-num=2 --file-total-size=4G --file-test-mode=rndrw cleanup
# 顺序写
sysbench --threads=4 --report-interval=4 --time=60 --test=fileio --file-num=2 --file-total-size=4G --file-test-mode=seqwr prepare
sysbench --threads=4 --report-interval=4 --time=60 --test=fileio --file-num=2 --file-total-size=4G --file-test-mode=seqwr run
sysbench --threads=4 --report-interval=4 --time=60 --test=fileio --file-num=2 --file-total-size=4G --file-test-mode=seqwr cleanup
# 顺序读
sysbench --threads=4 --report-interval=4 --time=60 --test=fileio --file-num=2 --file-total-size=4G --file-test-mode=seqrd prepare
sysbench --threads=4 --report-interval=4 --time=60 --test=fileio --file-num=2 --file-total-size=4G --file-test-mode=seqrd run
sysbench --threads=4 --report-interval=4 --time=60 --test=fileio --file-num=2 --file-total-size=4G --file-test-mode=seqrd cleanup
```

#### dd 顺序写

```bash
dd if=/dev/zero of=benchtest_$$ bs=512k count=2048 conv=fdatasync && rm -f benchtest_$$
```

### 网络

#### 传输速率(pps)

```bash
# server & client 编译安装 netserver
wget -c "https://codeload.github.com/HewlettPackard/netperf/tar.gz/netperf-2.5.0" -O netperf-2.5.0.tar.gz
yum -y install gcc cc 
tar zxvf netperf-2.5.0.tar.gz
cd netperf-netperf-2.5.0
./configure && make && make install

# server 端启动 netserver
netserver
# 监控数据
sar -n DEV 5

# client 端测试
netperf -t UDP_STREAM -H <server ip> -l 100 -- -m 64 -R 1 &
# 监控数据
sar -n DEV 5
```

```bash
# 结果分析，看 rxpck/s,txpck/s 值即可，值越大，性能越好
```

 <img src="https://clay-blog.oss-cn-shanghai.aliyuncs.com/img/image-20240301183938233.png"  style="zoom:50%;" />

#### 网络带宽

```bash
# server 端启动 netserver
netserver
# 监控数据
sar -n DEV 5
 
# client 端测试
netperf -t TCP_STREAM -H <server ip> -l 100 -- -m 1500 -R 1 &
# 监控数据
sar -n DEV 5
```

```bash
# 结果分析，看 rxkB/s,txkB/s 值即可，值越大，性能越好
```

 <img src="https://clay-blog.oss-cn-shanghai.aliyuncs.com/img/image-20240301215710451.png" style="zoom:50%;" />

#### 单向时延

```bash
# 服务端：
yum install -y sockperf
sockperf sr --daemonize > /dev/null 2>&1
 
# 客户端：
sockperf under-load -i serverip  --mps=100000 -t 300 -m 14 --reply-every=50 --full-log=sockperf.out
 
# mps: 每秒多少请求   -t 测试时间 -m 每个请求大小(默认14byte)
```

#### ping时延

```bash
ping -c 30 同网段其他主机
```

## 应用性能测试

### Nginx

```bash
# 安装 ab 工具
yum -y install httpd-tools

# 编译安装 wrk
git clone https://github.com/wg/wrk.git
make
cp wrk /usr/local/bin/
 
# 测试，-c表示并发连接数1000，-t表示线程数为2，-d 表示测试时间
wrk -t12 -c400 -d30s <URL>
 
#默认长连接，短链接：-H “Connection:Close”
 
# ab 
## ab -c 400 -n 1000000 <URL>
```

```bash
# 结果分析，Requests/sec 为 QPS
```

 <img src="https://clay-blog.oss-cn-shanghai.aliyuncs.com/img/image-20240301222852837.png" alt="image-20240301222852837" style="zoom:50%;" />

### MySQL

```bash
# 安装
yum install -y mariadb-server
create database pressure
grant all on pressure.* to 'pressure'@'127.0.0.1' identified by 'pressure';
 
yum install -y sysbench
# 造数据：
sysbench --db-driver=mysql --time=300 --threads=10 --report-interval=1 --mysql-host=127.0.0.1 --mysql-port=3306 --mysql-user=pressure --mysql-password=pressure --mysql-db=pressure --tables=20 --table_size=1000000 oltp_read_write --db-ps-mode=disable prepare
 
# 常规压测（包含读写）
sysbench --db-driver=mysql --time=300 --threads=10 --report-interval=1 --mysql-host=127.0.0.1 --mysql-port=3306 --mysql-user=pressure --mysql-password=pressure --mysql-db=pressure --tables=20 --table_size=1000000 oltp_read_write --db-ps-mode=disable run
```

### Redis

```bash
# 安装
yum install -y redis
service redis start
 
# 压测：
redis-benchmark -t set,get -n 1000000
```

## 自动化压测脚本

> 压测需要大量采样，并实时观察

```bash
git clone https://github.com/clay-wangzhi/bench.git
bash bench.sh
```

 <img src="https://clay-blog.oss-cn-shanghai.aliyuncs.com/img/image-20240301225244059.png"  style="zoom:50%;" />
