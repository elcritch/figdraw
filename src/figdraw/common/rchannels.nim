## Compatibility import for the RChan implementation now maintained by Sigils.
##
## New code should import `sigils/rchannels` directly. This module remains so
## existing FigDraw imports continue to resolve while callers migrate.

import sigils/rchannels

export rchannels
