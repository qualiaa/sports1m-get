# call as 
# python gen_clip_times.py $length $seconds_per_clip $n_clips

import sys
from random_intervals import random_intervals

length = int(float(sys.argv[1]))
seconds_per_clip = int(sys.argv[2])
n_clips  = int(sys.argv[3])


try:
    for interval in random_intervals(length,seconds_per_clip,n_clips):
        print(interval.start)
except ValueError:
    sys.exit(2)
