# 在Windows下基于mysql8.0 和 docker的 mysql 主从复制

### 1. 初始文件夹结构

│   mysql.yml
│   
├───master
│   ├───conf
│   │       my.cnf
│   │       
│   └───init
│           init.sql
│           
└───slave
    └───conf
            my.cnf

master和slave的conf文件下需要有一个my.cnf，两者略有不同。提前放置在文件夹中，挂载进容器，是为了方便后面不再写入。

master 的init 文件下的 init.sql 脚本是为了，建立容器后，自动建立一个用于主从复制的用户 slave。

### 2. 文件准备

#### 2.1 master 和 slave 的docker-compose yml 文件

```yaml
version: "3"
services:
  mysql-master:
    image: mysql:8.0
    container_name: mysql-master
    privileged: true
    restart: "no"
    volumes:
      - ./master/db:/var/lib/mysql
      - ./master/log:/var/log/mysql
      - ./master/conf:/etc/mysql/conf.d
      - ./master/init:/docker-entrypoint-initdb.d/
    environment:
      - MYSQL_ROOT_PASSWORD=root
    ports:
      - "3307:3306"
    command: --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
    
  mysql-slave:
    image: mysql:8.0
    container_name: mysql-slave
    privileged: true
    restart: "no"
    volumes:
      - ./slave/db:/var/lib/mysql
      - ./slave/log:/var/log/mysql
      - ./slave/conf:/etc/mysql/conf.d
    environment:
      - MYSQL_ROOT_PASSWORD=root
    ports:
      - "3308:3306"
    command: --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
```

#### 2.2 master 的 my.cnf

```mysql
[mysqld]
## 设置server_id, 同一个局域网中需要唯一
server_id=101
## 指定不需要同步的数据库名称
binlog-ignore-db=mysql
## 开启二进制日志功能
log-bin=mall-mysql-bin
## 设置二进制日志使用内存大小（事务）
binlog_cache_size=1M
## 设置使用的二进制日志格式（mixed,statement,row）
binlog_format=mixed
## 二进制日志过期清理时间。默认值为0，表示不自动清理
expire_logs_days=7
## 跳过主从复制中遇到的所有错误或指定类型的错误，避免slave端复制中断
## 如：1062错误是指一些主键重复，1032错误是因为主从数据库数据不一致
slave_skip_errors=1062
```

#### 2.3 slave 的 my.cnf

```mysql
[mysqld]
## 设置server_id, 同一个局域网内需要唯一
server_id=102
## 指定不需要同步的数据库名称
binlog-ignore-db=mysql
## 开启二进制日志功能，以备slave作为其它数据库实例的Master时使用
log-bin=mall-mysql-slave1-bin
## 设置二进制日志使用内存大小（事务）
binlog_cache_size=1M
## 设置使用的二进制日志格式（mixed,statement,row）
binlog_format=mixed
## 二进制日志过期清理时间。默认值为0，表示不自动清理
expire_logs_days=7
## 跳过主从复制中遇到的所有错误或指定类型的错误，避免slave端复制中断
## 如：1062错误是指一些主键重复，1032是因为主从数据库数据不一致
slave_skip_errors=1062
## relay_log配置中继日志
relay_log=mall-mysql-relay-bin
## log_slave_updates表示slave将复制事件写进自己的二进制日志
log_slave_updates=1
## slave设置只读（具有super权限的用户除外）
read_only=1
```

#### 2.4 master 的 init.sql

```mysql
create user 'slave'@'%' identified by 'slave';
grant replication slave, replication client on *.* to 'slave'@'%';
flush privileges;
```

### 3. 步骤

#### 3.1 运行yml 文件，建立master 和 slave 容器

```bash
docker-compose -f mysql.yml -d up
```

#### 3.2 进入master容器，查看主从同步状态，得到两个值备用

```bash
docker exec -it mysql-master /bin/bash
mysql -uroot -p
show master status;
```

#### 3.3 正常情况下，你应该得到这样一个图

mysql> show master status;

|         File          | Position | Binlog_Do_DB | Binlog_Ignore_DB | Executed_Gtid_Set |
| :-------------------: | :------: | :----------: | :--------------: | :---------------: |
| mall-mysql-bin.000003 |   157    |              |      mysql       |                   |

#### 3.4 改写按照上面的值，改写下面的语句(注意自己主机的IP地址)

```mysql
change master to master_host='192.168.1.109',master_user='slave',master_password='slave',master_port=3307,master_log_file='mall-mysql-bin.000003',master_log_pos=157,master_connect_retry=30,GET_MASTER_PUBLIC_KEY=1;
```

#### 3.5 进入slave容器，将上面的语句执行

```bash
docker exec -it mysql-master /bin/bash
mysql -uroot -p
```

```mysql
change master to master_host='192.168.1.109',master_user='slave',master_password='slave',master_port=3307,master_log_file='mall-mysql-bin.000003',master_log_pos=157,master_connect_retry=30,GET_MASTER_PUBLIC_KEY=1;
```

#### 3.6 查看主从同步状态

```mysql
# \G 可以将横向的结果集表格转换成纵向展示。
# slave status的字段比较多，纵向展示比友好
show slave status \G;
```

 Slave_IO_Running`、`Slave_SQL_Running 这两个字段应该是 NO

#### 3.7 开启主从同步

```mysql
start slave；
```

再次查看主从同步，Slave_IO_Running`、`Slave_SQL_Running应该变为 YES

#### 3.8 测试主从复制

##### 3.8.1 在主数据库上新建库、使用库、新建表、插入数据在主数据库上新建库、使用库、新建表、插入数据

```
create database db01;
use db01;
create table t1 (id int, name varchar(20));
insert into t1 values (1, 'abc');
```

##### 3.8.2 在从数据库上使用库、查看记录 

```
show databases;
use db01;
select * from t1;
```



