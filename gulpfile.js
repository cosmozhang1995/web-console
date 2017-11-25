var gulp = require('gulp');
var rename = require('gulp-rename');
var sass = require('gulp-sass');
var coffee = require('gulp-coffee');
var browserify = require('gulp-browserify');
var sourcemaps = require('gulp-sourcemaps');
var app = require('./app');

gulp.task('default', ['sass', 'script', 'server', 'watch']);

gulp.task('server', function() {
  var port = 3000;
  app.listen(port);
});

gulp.task('sass', function() {
  return gulp.src('public/scss/style.scss')
    .pipe(sass())
    .pipe(gulp.dest('public/stylesheets'))
});

gulp.task('script', function() {
  // gulp.src('public/coffee/*.coffee')
  //   .pipe(sourcemaps.init())
  //   .pipe(coffee())
  //   .pipe(sourcemaps.write())
  //   .pipe(gulp.dest('./dest/js'));
  gulp.src('public/coffeescripts/script.coffee', { read: false })
    .pipe(browserify({
      transform: ['coffeeify'],
      extensions: ['.coffee'],
      debug: true
    }))
    .pipe(rename('script.js'))
    .pipe(gulp.dest('public/javascripts'));
});

gulp.task('watch', function() {
  gulp.watch('public/scss/**/*.scss', ['sass']);
  gulp.watch('public/coffeescripts/**/*.coffee', ['script']);
});