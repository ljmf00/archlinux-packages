# Maintainer: Mark Weiman <mark dot weiman at markzz dot com>

_gemname=fpm
pkgname=$_gemname
pkgver=1.4.0
pkgrel=1
pkgdesc='Effing package management! Build packages for multiple platforms (deb, rpm, etc) with great ease and sanity.'
arch=(any)
url="https://github.com/jordansissel/${_gemname}"
license=('Apache License (2.0)')
depends=(ruby ruby-cabin ruby-backports ruby-arr-pm ruby-clamp
         ruby-childprocess)
options=(!emptydirs)
source=("https://github.com/jordansissel/fpm/archive/v${pkgver}.tar.gz")
sha256sums=('e17ff7dabcc381945d4c697435cd2a3ea24d456b027f6b3321f09f2b3e94575b')

build() {
  cd $srcdir/$_gemname-$pkgver
  sed -i 's/"clamp", "~> 0.6"/"clamp", ">= 0.6"/' fpm.gemspec
  gem build fpm.gemspec 2> /dev/null $1
}

package() {
  local _gemdir="$(ruby -e'puts Gem.default_dir')"
  gem install --ignore-dependencies --no-user-install -i "$pkgdir/$_gemdir" -n "$pkgdir/usr/bin" $srcdir/$_gemname-$pkgver/$_gemname-$pkgver.gem
  rm "$pkgdir/$_gemdir/cache/$_gemname-$pkgver.gem"
  install -D -m644 "$pkgdir/$_gemdir/gems/$_gemname-$pkgver/LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
