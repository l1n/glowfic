BASEDIR=~/git/glowfic
DIFFERENCE=test

function execute () {
  if check_dir $1; then
    if confirm $2 $3; then
      update $1;
    fi
  fi
}

function check_dir () {
  path=$BASEDIR/tmp/spec/expectation/renders_the_same/$1/$DIFFERENCE.png
  # echo "Checking ${path} exists..."
  [ -f $path ]
}

function confirm () {
  read -p "Update ${1} ${2}? y/n " -n 1 -r
  echo    # (optional) move to a new line
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    return 1
  else
    return 0
  fi
}

function update () {
  expectation_path=$BASEDIR/spec/expectation/renders_the_same/$1/expected.png
  test_path=$BASEDIR/tmp/spec/expectation/renders_the_same/$1/test.png
  #echo "Deleting ${expectation_path}"
  #rm $expectation_path
  #echo "Copying ${test_path} to ${expectation_path}"
  echo "Updating..."
  mv -Tu $test_path $expectation_path
}


for dir in dark default iconless monochrome river starry starrydark starrylight; do
  for subdir in board character_edit gallery recently_updated user_edit; do
    path=$dir/behaves_like_layout/$subdir
    execute $path $dir $subdir
  done

  for postdir in icon_picker post post_edit post_stats; do
    path=$dir/behaves_like_layout/with_post/$postdir
    execute $path $dir $postdir
  done
done
