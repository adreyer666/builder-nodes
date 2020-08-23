#!/usr/bin/env make

BUILD = default

  DIR := $(shell pwd)
 NAME := $(shell basename $(DIR))
IMAGE = $(NAME)_$(BUILD)

build:
	vagrant up --provider=libvirt
	vagrant ssh-config --host vagrant-$(NAME) >> ~/.ssh/config.d/vagrant-$(NAME).conf
	vagrant ssh-config --host $(NAME) | grep -vE 'User|IdentityFile' > ~/.ssh/config.d/$(NAME).conf
	ssh -X vagrant-$(NAME)

run:
	virsh start $(IMAGE)
	ssh -X vagrant-$(NAME)

pause:
	virsh managedsave $(IMAGE)

clean:
	-rm ~/.ssh/config.d/vagrant-$(NAME).conf
	-virsh destroy $(IMAGE)
	-vagrant destroy -f
	-virsh undefine $(IMAGE)

