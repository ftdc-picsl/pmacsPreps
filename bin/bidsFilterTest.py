#!/usr/bin/env python3
import argparse
import bids
from bids import BIDSLayout
import os
from pathlib import Path

def _filter_pybids_none_any(dct):
    import bids
    return {
        k: bids.layout.Query.NONE
        if v is None
        else (bids.layout.Query.ANY if v == "*" else v)
        for k, v in dct.items()
    }


def _bids_filter(value):
    from json import loads
    from bids.layout import Query

    if value and Path(value).exists():
        try:
            filters = loads(Path(value).read_text(), object_hook=_filter_pybids_none_any)
        except Exception as e:
            raise Exception("Unable to parse BIDS filter file. Check that it is "
                            "valid JSON.")
    else:
        raise Exception("Unable to load BIDS filter file " + value)

    # unserialize pybids Query enum values
    for acq, _filters in filters.items():
        filters[acq] = {
            k: getattr(Query, v[7:-4])
            if not isinstance(v, Query) and "Query" in v
            else v
            for k, v in _filters.items()
        }
    return filters

def collect_data(bids_dir, participant_label, queries, filters=None, bids_validate=True):
    """
    Uses pybids to retrieve the input data for a given participant
    """
    if isinstance(bids_dir, BIDSLayout):
        layout = bids_dir
    else:
        layout = BIDSLayout(str(bids_dir), validate=bids_validate)

    bids_filters = filters or {}
    for acq, entities in bids_filters.items():
        queries[acq].update(entities)

    subj_data = {
        dtype: sorted(
            layout.get(
                return_type="file",
                subject=participant_label,
                extension=["nii", "nii.gz"],
                **query
            )
        )
        for dtype, query in queries.items()
    }

    return subj_data, layout



qsiprep_queries = {
    'fmap': {'datatype': 'fmap'},
    'sbref': {'datatype': 'func', 'suffix': 'sbref'},
    'flair': {'datatype': 'anat', 'suffix': 'FLAIR'},
    't2w': {'datatype': 'anat', 'suffix': 'T2w'},
    't1w': {'datatype': 'anat', 'suffix': 'T1w'},
    'roi': {'datatype': 'anat', 'suffix': 'roi'},
    'dwi': {'datatype': 'dwi', 'suffix': 'dwi'}
}

fmriprep_queries = {
    'fmap': {'datatype': 'fmap'},
    'bold': {'datatype': 'func', 'suffix': 'bold'},
    'sbref': {'datatype': 'func', 'suffix': 'sbref'},
    'flair': {'datatype': 'anat', 'suffix': 'FLAIR'},
    't2w': {'datatype': 'anat', 'suffix': 'T2w'},
    't1w': {'datatype': 'anat', 'suffix': 'T1w'},
    'roi': {'datatype': 'anat', 'suffix': 'roi'}
}

parser = argparse.ArgumentParser(description='BIDS validation and filter preview. The filters are processed using code extracted from qsiprep '
                                 'v 0.14.2. I believe fmriprep works the same way, but I have not verified this. Also, it is possible that '
                                 'different versions of pybids will behave differently. With those disclaimers in mind, running this can '
                                 'highlight obvious problems with filters or allow you to experiment with advanced matching.')
parser.add_argument('--bids-dir', help='The directory with the input dataset formatted according to the BIDS standard.', required = True)
parser.add_argument('--filter-file', help='File containing BIDS filters', required = True)
parser.add_argument('--participant-label', help='The label of the participant that should be analyzed. The label '
                   'corresponds to sub-<participant> from the BIDS spec (so it does not include "sub-").', required = True)
parser.add_argument('--prep-modality', help='The kind of modality prep to test the filter on. Options are fmri, qsi.', required = True)

bids.config.set_option('extension_initial_dot', True)

args = parser.parse_args()

layout = BIDSLayout(args.bids_dir, validate = True)

filters = _bids_filter(args.filter_file)

queries = None

if (args.prep_modality == 'qsi'):
    queries = qsiprep_queries
elif (args.prep_modality == 'fmri'):
    queries = fmriprep_queries
else:
    raise ValueError(f'Unsupported modality prep string {args.prep_modality}')


sub_data, layout = collect_data(layout, args.participant_label, queries, filters = filters)

print(f'\n\n Filtered data for participant {args.participant_label}:\n')

for k, v in sub_data.items():
    print (k, '\t:\t', v)
