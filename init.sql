create user 'slave'@'%' identified by 'slave';
grant replication slave, replication client on *.* to 'slave'@'%';
flush privileges;