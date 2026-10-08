-- Value used as an initial default height for BlizzMeter entry bars.
--
-- This is just used as a consistent dummy value in the absence of any
-- height configuration, eg. before edit mode settings have loaded.
BLIZZMETER_DEFAULT_BAR_HEIGHT = 25;

-- Value used as an initial default bar spacing for BlizzMeter entry bars.
--
-- This is just used as a consistent dummy value in the absence of any
-- height configuration, eg. before edit mode settings have loaded.
BLIZZMETER_DEFAULT_BAR_SPACING = 4;

-- Edit Mode stores text size in units scaled from 0 to 100 (and higher as
-- we allow oversizing the text). Internally, the meter converts this to
-- a text scale that we want to represent on a range of 0 to 1.
BLIZZMETER_TEXT_SIZE_TO_SCALE_MULTIPLIER = 0.01;

-- Edit Mode also stores transparency in 0 to 100 units.
BLIZZMETER_TRANSPARENCY_TO_ALPHA_MULTIPLIER = 0.01;

-- BlizzMeter: shapes for class and spec icons on the bars (spell icons are always square).
BLIZZMETER_ICON_SHAPE_SQUARE = 1;
BLIZZMETER_ICON_SHAPE_CIRCLE = 2;
BLIZZMETER_ICON_SHAPE_RING = 3; -- Circle framed by the services-cover-ring atlas.

-- How far the circular mask is inset from the icon's edges so the icon sits inside the ring.
BLIZZMETER_ICON_RING_INSET = 2;
