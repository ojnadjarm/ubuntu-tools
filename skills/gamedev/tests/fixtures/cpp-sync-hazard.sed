# Zeroes the src stage of the template's acquire->attachment barrier in src/renderer.cpp (execution dependency removed): core validation passes, syncval must report SYNC-HAZARD.
/transition(cmd, image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,/{n;s/VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, 0,/VK_PIPELINE_STAGE_2_NONE, 0,/}
