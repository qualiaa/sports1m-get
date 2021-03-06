# call as 
# python extract_clips.py $frame_folder $output_folder $frames_per_sample $n_samples

import os,re,sys
import os.path as path
import shutil
from glob import glob
from random_intervals import random_intervals

def _resize_frame_tensor(frame_tensor,target_shape):
    target_shape=(frame_tensor.shape[0],*target_shape,frame_tensor.shape[-1])
    return resize(frame_tensor,target_shape,anti_aliasing=True,mode='reflect')

frame_folder = sys.argv[1]
clip_folder  = sys.argv[2]
frames_per_sample,n_samples = [int(a) for a in sys.argv[3:]]


file_list = glob(path.join(frame_folder,"frame*"))
file_list.sort(key=lambda x: int(re.search("frame([0-9]{6})",x)[1]))

try:
    intervals = random_intervals(population_size=len(file_list),
                                 sample_size=frames_per_sample,
                                 n_samples=n_samples)
except ValueError:
    sys.exit(2)

for i,interval in enumerate(intervals):
    output_dir = path.join(clip_folder,str(i))
    os.makedirs(output_dir)
    for j,frame in enumerate(file_list[interval]):
        output_file = "{:03d}.{:s}".format(j,frame.rsplit('.',1)[-1])
        shutil.copy(frame,path.join(output_dir,output_file))
