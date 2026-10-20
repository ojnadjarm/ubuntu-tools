# excerpt of hero-film/build.sh plate(): the 3D title goes on shot 1 only
  MV_TITLE=$([[ $i == 1 ]] && echo "$TITLE") MV_MODEL=$HERO MV_MODEL_ANIM=${CLIPS[$i]} MV_FOG=$FOG \
