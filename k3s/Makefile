#!/usr/bin/env make

BUILD = default

  DIR := $(shell pwd)
 NAME := $(shell basename $(DIR))
IMAGE = $(NAME)_$(BUILD)


build: id_rsa.pub
	vagrant up --provider=libvirt 2>&1 | tee make.log
	vagrant ssh-config > ~/.ssh/config.d/vagrant-$(NAME).conf

id_rsa.pub:
	ssh-keygen -q -t rsa -b 4096 -f $(DIR)/id_rsa -N ''

run:
	ssh -X minikube

stop:
	-vagrant destroy -f

clean: stop
	-rm -f ~/.ssh/config.d/vagrant-$(NAME).conf

