# The three frozen cameras each world is captured from, as name:arg pairs for
# window.__poemShot. Sourced by shoot.sh (pictures) and world.sh (scene data)
# so both look at exactly the same eyes.
#   . shared/cams.sh; world_cams <world>   →  sets $SHOTS and $DEFAULT_PORT
world_cams() {
  case "$1" in
    gitanjali-60)
      SHOTS="1-arrival:1 2-children:2 6-above:6"
      DEFAULT_PORT=8731
      ;;
    chunjiang)
      SHOTS="1-moonrise:1 4-sandbar:4 5-boat:5"
      DEFAULT_PORT=8732
      ;;
    xiangfuren)
      SHOTS="1-beizhu:2,-58,0,-0.05 5-chengwang:0,-62,3.1416,-0.06 6-dengdai:-70,46,-0.575,-0.02"
      DEFAULT_PORT=8793
      ;;
    *)
      echo "unknown world: $1" >&2
      return 1
      ;;
  esac
}
