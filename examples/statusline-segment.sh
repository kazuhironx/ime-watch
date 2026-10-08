# Claude Code の statusLine スクリプトに貼る断片 (bash)。
# ime-watch が書いた入力モードを、ひらがな等なら橙地、英数なら灰色で出す。
# 切り替えを数秒以内に反映させるには settings.json の statusLine に
# "refreshInterval": 2 を付ける。
ime=$(cat "${XDG_CACHE_HOME:-$HOME/.cache}/ime-state" 2>/dev/null)
case "$ime" in
  "") ime_seg="" ;;
  A)  ime_seg='\033[38;5;244m[A]\033[0m ' ;;
  *)  ime_seg="\033[38;5;16m\033[48;5;215m\033[1m ${ime} \033[0m " ;;
esac
printf '%b' "$ime_seg"
