#!/usr/bin/env make

BUILD = default

  DIR := $(shell pwd)
 NAME := $(shell basename $(DIR))
IMAGE = $(NAME)_$(BUILD)

build: checkcfg route
	vagrant up --provision --provider=libvirt 2>&1 | tee make.log
	vagrant ssh-config > ~/.ssh/config.d/vagrant-$(NAME).conf

checkcfg:
	jq . < kcluster-config.json >/dev/null

route:
	-#sudo ip route add 192.168.121.0/24 via 192.168.1.10
	-#sudo ip route add 172.16.17.0/24 via 192.168.1.10
	-# echo "$(DIR) 192.168.121.0/24(rw)" | sudo tee -a /etc/exports
	-sudo exportfs -rav

run:
	ssh -X kjump1
	ssh -X kmaster1

stop:
	-vagrant destroy -f

clean: stop
	-rm -f status/sec.json status/kube.config status/subnet.env
	-rm -rf tmp/* make.log
	-rm -f ~/.ssh/config.d/vagrant-$(NAME).conf

