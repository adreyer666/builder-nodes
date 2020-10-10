#!/usr/bin/env make

BUILD = default

  DIR := $(shell pwd)
 NAME := $(shell basename $(DIR))
IMAGE = $(NAME)_$(BUILD)

build:
	vagrant up --provider=libvirt 2>&1 | tee make.log
	vagrant ssh-config >> ~/.ssh/config.d/vagrant-$(NAME).conf

run:
	ssh -X kjump1
	ssh -X kmaster1

clean:
	-rm ~/.ssh/config.d/vagrant-$(NAME).conf
	-vagrant destroy -f

