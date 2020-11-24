#!/usr/bin/env make

BUILD = default

  DIR := $(shell pwd)
 NAME := $(shell basename $(DIR))
IMAGE = $(NAME)_$(BUILD)

build:
	vagrant up --provider=libvirt 2>&1 | tee make.log
	vagrant ssh-config > ~/.ssh/config.d/vagrant-$(NAME).conf

run:
	ssh -X minikube

stop:
	-vagrant destroy -f

clean: stop
	-rm -f ~/.ssh/config.d/vagrant-$(NAME).conf

