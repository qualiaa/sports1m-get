# call as 
# python extract_clips.py $video_folder $frames_per_sample $n_samples

import os,random,re,sys
import os.path as path
from glob import glob

def _resize_frame_tensor(frame_tensor,target_shape):
    target_shape=(frame_tensor.shape[0],*target_shape,frame_tensor.shape[-1])
    return resize(frame_tensor,target_shape,anti_aliasing=True,mode='reflect')

def random_intervals(population_size,sample_size,n_samples):
    if n_samples*sample_size > population_size:
        raise ValueError
    result=[]
    ranges=None
    population_ranges=list(slice(a,a+sample_size) for a in
            range(population_size-sample_size+1))
    while len(result) < n_samples:
        if not ranges:
            ranges = population_ranges.copy()
            result = []
        x = random.randrange(len(ranges))
        result.append(ranges[x])
        lb = x - sample_size if x >= sample_size else 0
        ranges = ranges[:lb] + ranges[x+sample_size:]
    return result

frame_folder = sys.argv[1]
clip_folder  = sys.argv[2]
frames_per_sample,n_samples = [int(a) for a in sys.argv[3:]]


file_list = glob(path.join(frame_folder,"frame*"))
file_list.sort(key=lambda x: int(re.search("frame([0-9]{6})",x)[1]))

intervals = random_intervals(population_size=len(file_list),
                             sample_size=frames_per_sample,
                             n_samples=n_samples)

for i,interval in enumerate(intervals):
    output_dir = path.join(clip_folder,str(i))
    os.makedirs(output_dir)
    for j,frame in enumerate(file_list[interval]):
        output_file = "{:03d}.{:s}".format(j,frame.rsplit('.',1)[-1])
        os.rename(frame,path.join(output_dir,output_file))
