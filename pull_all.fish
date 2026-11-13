#!/usr/bin/fish

for name in ~/dotfiles ~/WallPapers ~/AI_PROMPTS ~/.config/nvim
 echo "$name を git pull します"
 git -C $name pull && echo "$name を git pull しました"
end

sudo keyd reload
