#!/usr/bin/env bash

# DISCLAIMER: Only use for development or testing purposes. Only tested on Ubuntu 16.04 LTS.
# AUTHOR: Mario Harvey https://marioharvey.com
# set consul version
consul_version='0.6.4'

# set alpine os version
alpine_version='3.4'

# container names
names=(consul1 consul2 consul3)

command_exists () {
  type "$1" &> /dev/null ;
}

get_consul_ip(){
	lxc info "$1" | grep 'eth0:\sinet\s' | awk 'NR == 1 { print $3 }'
}

check_agent(){
  lxc exec "$1" -- ps -ef | grep 'consul\sagent' > /dev/null 2>&1
}

get_all_ips(){
  x=0
  echo 'getting IPs for Consul containers...'
  #get the ip for consul bootstrap instance
  while [ -z "$bootstrap_ip" -o -z "$consul2_ip" -o -z "$consul3_ip" ]
    do
      if [ "$x" -gt 30 ]; then echo 'Cannot get an IPs for the consul instances. Please check lxd bridge and try again. Cleaning...'; destroy; exit 2; fi
      bootstrap_ip=$(get_consul_ip "${names[0]}")
      consul2_ip=$(get_consul_ip "${names[1]}")
      consul3_ip=$(get_consul_ip "${names[2]}")
      ((x++))
      sleep 2
  done
}

check_one_ip(){
  x=0
  echo 'getting IPs for Consul containers...'
  #get the ip for consul bootstrap instance
  while [ -z "$ip" ]
    do
      if [ "$x" -gt 30 ]; then echo 'Cannot get an IPs for the consul instances. Please check lxd bridge and try again. Cleaning...'; destroy; exit 2; fi
      ip=$(get_consul_ip "$1")
      ((x++))
      sleep 2
  done
}

output(){
	echo '              lxd-consul setup complete!           '
	echo '***************************************************'
	echo '                    consul ui links                ' 
	echo "             * http://$bootstrap_ip:8500           "
	echo "             * http://$consul2_ip:8500             "
	echo "             * http://$consul3_ip:8500             "
	echo '***************************************************'
}

start(){
	echo 'starting consul containers...'
	lxc start "${names[0]}" "${names[1]}" "${names[2]}"
	if [ $? -gt 0 ]; then echo 'want a consul cluster? run: ./lxd-consul.sh create!'; exit 1; fi
    get_all_ips
    echo 'bringing up consul bootstrap container...'
    lxc exec "${names[0]}" -- rc-service consul-bootstrap start > /dev/null 2>&1
    echo 'restarting consul server containers...'
    lxc exec "${names[1]}" -- rc-service consul-server restart > /dev/null 2>&1
    lxc exec "${names[2]}" -- rc-service consul-server restart > /dev/null 2>&1
	output
}

stop(){
	echo 'stopping consul containers...'
	lxc exec "${names[2]}" -- rc-service consul-server stop > /dev/null 2>&1
	lxc exec "${names[1]}"-- rc-service consul-server stop > /dev/null 2>&1
	lxc exec "${names[0]}" -- rc-service consul-bootstrap stop > /dev/null 2>&1 && \
  rc-service consul-server stop > /dev/null 2>&1
	lxc stop "${names[0]}" "${names[1]}" "${names[2]}" > /dev/null 2>&1
}

restart(){
	echo 'restarting consul containers...'
	stop
	start
}

destroy(){
	echo 'destroying lxd-consul cluster...'
	# stopping cluster
  stop
	# delete containers
	echo 'deleting consul containers...'
	lxc delete -f "${names[0]}" "${names[1]}" "${names[2]}"
	echo 'lxd-consul destroyed!'
}

verify_running() {
  # check if containers exist and are already running consul
  i=0
  for name in "${names[@]}";
    do
       # if constainer exists start it
       if lxc info "$name" > /dev/null 2>&1; then
        lxc start "$name" > /dev/null 2>&1
        check_one_ip "$name"  > /dev/null 2>&1
        lxc exec "$name" -- rc-service consul-server start > /dev/null 2>&1
       fi
       # check for running consul agents
       if check_agent "$name" > /dev/null 2>&1; then
        echo "$name is already running with consul agent!"
        ((i++))
       fi
  done

  if [ "$i" -eq 3 ]; then
    echo 'Consul cluster already running on lxd containers.'
    echo 'You can restart or stop with ./lxd-consul.sh restart/stop'
    echo "Usage: $0 command {options:create,destroy,start,stop,restart}"
    exit 1
  fi

}

create() {
  verify_running
  # check if lxc client is installed. if not exit out and tell to install
  if command_exists lxc; then
  	echo 'lxc client appears to be there. Proceeding with cluster creation...'
  	sleep 1
  else
  	echo 'lxd does not appear to be installed properly. Follow instructions here: https://linuxcontainers.org/lxd/getting-started-cli'
    exit 1
  fi
  
  # launch alpine container, install go, and install consul
  for name in "${names[@]}";
    do
      # create containers
      lxc launch images:alpine/$alpine_version/amd64 "$name" -c 'environment.GOPATH=/go' -c 'security.privileged=true'
      # make consul dirs
      lxc exec "$name" -- sh -c "mkdir -p /consul/data /consul/server"
  done
  
  lxc exec "${names[0]}" -- sh -c "echo http://dl-6.alpinelinux.org/alpine/v3.4/main > /etc/apk/repositories && \
  echo http://dl-5.alpinelinux.org/alpine/v3.4/main >> /etc/apk/repositories && \
  echo http://dl-4.alpinelinux.org/alpine/v3.4/main >> /etc/apk/repositories && \
  echo http://dl-3.alpinelinux.org/alpine/v3.4/main >> /etc/apk/repositories && \
  echo http://dl-2.alpinelinux.org/alpine/v3.4/main >> /etc/apk/repositories && \
  apk add ca-certificates wget --no-cache && \
  update-ca-certificates && \
  wget https://releases.hashicorp.com/consul/$consul_version/consul_\"$consul_version\"_linux_amd64.zip -O consul_$consul_version.zip && \
  unzip -o consul_$consul_version.zip -d /usr/bin && \
  rm -f consul_$consul_version.zip && \
  chmod 755 /usr/bin/consul && \
  mkdir -p /consul/bootstrap"

  lxc file pull "${names[0]}"/usr/bin/consul .

  lxc file push --mode=0755 consul "${names[1]}"/usr/bin/consul

  lxc file push --mode=0755 consul "${names[2]}"/usr/bin/consul

  rm -f consul

  get_all_ips

  # create bootstrap config with ip address
  sed s/myaddress/"$bootstrap_ip"/g config/bootstrap.json > bootstrap_consul1.json
  # move in bootstrap config into container into bootstrap directory
  lxc file push bootstrap_consul1.json "${names[0]}"/consul/bootstrap/
  # move in bootstrap init script and make executable
  lxc file push config/consul-bootstrap "${names[0]}"/etc/init.d/
  lxc exec "${names[0]}" -- chmod 755 /etc/init.d/consul-bootstrap
  # launch bootstrap if consul not already bootstrapped
  if lxc exec "${names[0]}" -- cat /consul/data/raft/peers.json > /dev/null 2>&1; then
    lxc exec "${names[0]}" -- rc-service consul-bootstrap stop > /dev/null 2>&1
    lxc exec "${names[0]}" -- rc-service consul-server start
  else
    lxc exec "${names[0]}" -- rc-service consul-bootstrap start
  fi
  #create server configlxc file push config/consul-server consul1/etc/init.d/  files
  sed s/ips/"$bootstrap_ip\", \"$consul3_ip"/g config/server.json > server_consul2.json
  sed s/ips/"$bootstrap_ip\", \"$consul2_ip"/g config/server.json > server_consul3.json
  sed s/ips/"$consul2_ip\", \"$consul3_ip"/g config/server.json > server_consul1.json
  
  # push server config files and init script to server nodes
  for name in "${names[@]}";
    do
    lxc file push server_"$name".json $name/consul/server/
    lxc file push config/consul-server $name/etc/init.d/
    lxc exec $name -- chmod 755 /etc/init.d/consul-server
    lxc exec $name -- rc-update add consul-server default
  done
  
  #start server nodes
  lxc exec "${names[1]}" -- rc-service consul-server start
  lxc exec "${names[2]}" -- rc-service consul-server start
  
  # cleanup
  rm -f *_consul*

  # print ips of cluster
  output

}

case "$1" in
	create)
      create
      ;;
    destroy)
      destroy
      ;;
    start)
      start
      ;;
    stop)
      stop
      ;;
    restart)
      restart
      ;;
    *) 
      echo "Usage: $0 command {options:create,destroy,start,stop,restart}"
      exit 1
esac
