#!/usr/bin/env python3
# GPLv2 license, spit out /proc/schedstat
# this works with schedstat v15

import sys,os, time

cpustat_txt = [ 'cpu zeros', # 0
                'sched_yied()', # 1
                'zeros',
                'schedule()', # 3
                'sched->idle()', #4
                'try_to_wake_up()', #5
                'try_to_wakeup(local)', #6
                'run time', #7
                'wait time', #8
                'timeslices,' #9
                ]
                
domain_txt = [ 'domain zeros', #0
               'IDLE lb_count', #1
               'IDLE lb_balanced', #2
               'IDLE lb_failed', #3
               'IDLE lb_imbalance', #4
               'IDLE lb_gained', #5
               'IDLE lb_hot_gained', #6
               'IDLE lb_nobusyq', #7
               'IDLE lb_nobusyg', #8
               'BUSY lb_count', #9
               'BUSY lb_balanced', #10
               'BUSY lb_failed', #11
               'BUSY lb_imbalance', #12
               'BUSY lb_gained', #13
               'BUSY lb_hot_gained', #14
               'BUSY lb_nobusyq', #15
               'BUSY lb_nobusyg', #16
               'NEW IDLE lb_count', #17
               'NEW IDLE lb_balanced', #18
               'NEW IDLE lb_failed', #19
               'NEW IDLE lb_imbalance', #20
               'NEW IDLE lb_gained', #21
               'NEW IDLE lb_hot_gained', #22
               'NEW IDLE lb_nobusyq', #23
               'NEW IDLE lb_nobusyg', #24
               'alb_count', #25
               'alb_failed', #26
               'alb_pushed', #27
               'sbe_count', #28
               'sbe_balanced', #29
               'sbe_pushed', #30
               'sbf_count', #31
               'sbf_balanced', #32
               'sbf_pushed', #33
               'ttwu_wake_remote', #34
               'ttwu_move_affine', #35
               'ttwu_move_balance', #36
               ]

def add_at_index(ar, index, val):
    while index >= len(ar):
        ar.append(0)
    ar[index] += val
    
def diff_arrays (start, now, seconds):
    results = []
    for i in range(0, len(start)):
        val = float(now[i] - start[i]) / seconds
        results.append(round(val, 2))
        if results[i] < 0:
            results[i] = 0
    return results

def read_schedstat():
    stats = open('/proc/schedstat', 'r')
    cpustat = []
    domainstat = []
    while True:
        l = stats.readline()
        if not l:
            break;

        if l.startswith('cpu'):
            words = l.split()
            for i in range(1, len(words)):
                add_at_index(cpustat, i, int(words[i]))

        if l.startswith('domain'):
            # the documentation starts counting assuming domainN cpumask are
            # one field
            words = l.split()[1:]
            for i in range(2, len(words)):
                add_at_index(domainstat, i, int(words[i]))
    return (cpustat, domainstat)
            
def print_stat(label, desc, ar):
    c = 0
    max_width = 0

    for x in desc:
        if len(x) > max_width:
            max_width = len(x)

    print(label)
    for i in range(0, len(ar)):
        print(f'#{i} {desc[i]:<{max_width}} {ar[i]:<20}', end=' ')
        c += 1
        if c % 1 == 0:
            print("")
    if c % 1 != 0:
            print("")

start_time = time.time()
last_cpustat, last_domainstat = read_schedstat()
sleep_time = 1

if len(sys.argv) > 1:
    sleep_time = int(sys.argv[1])

while True:
    time.sleep(sleep_time)
    now_time = time.time()
    cpustat, domainstat = read_schedstat()
    
    res_cpustat = diff_arrays(last_cpustat, cpustat, now_time - start_time)
    res_domainstat = diff_arrays(last_domainstat, domainstat, now_time - start_time)

    print_stat("cpu", cpustat_txt, res_cpustat)
    print_stat("domain", domain_txt, res_domainstat)

    last_cpustat = cpustat
    last_domainstat =  domainstat
    start_time = now_time
    

