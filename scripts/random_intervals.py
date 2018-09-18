import random

def random_intervals(population_size:int, sample_size:int,n_samples:int) -> [slice]:
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
