# Config files

Useful config files for preps.


# qsiprep

## eddy_config_prisma.json

This differs from the default qsiprep config by using a "quadratic" first level
model instead of the default "linear".

Matt Cieslak has recommended using "quadratic" for both first and second level
models. The FSL developers recommend using "none" or "linear", if the data is
sparsely sampled.

As a compromise between these options, this config specifies "quadratic" at the
first level and "linear" at the second level. This is a trade off between
correction ability, danger of overfitting, and computation time.

