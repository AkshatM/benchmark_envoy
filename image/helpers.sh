#!/bin/bash

logpid() { 
    while sleep 1; do  
        echo $(date) $(ps -p $1 -o pcpu= -o pmem=) ; 
    done; 
}

