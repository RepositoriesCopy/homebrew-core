class Couchdb < Formula
  desc "Apache CouchDB database server"
  homepage "https://couchdb.apache.org/"
  url "https://www.apache.org/dyn/closer.lua?path=couchdb/source/3.2.2/apache-couchdb-3.2.2.tar.gz"
  mirror "https://archive.apache.org/dist/couchdb/source/3.2.2/apache-couchdb-3.2.2.tar.gz"
  sha256 "69c9fd6f80133557f68a02e92dda72a4fd646d646f429f45bb8329a30f82f20e"
  license "Apache-2.0"
  revision 1

  livecheck do
    url :homepage
    regex(/href=.*?apache-couchdb[._-]v?(\d+(?:\.\d+)+)\.t/i)
  end

  bottle do
    sha256 cellar: :any,                 arm64_monterey: "ddb892cb6f2a02d4d1e5d6630aed89a48b6686c3381ce5a6349ed7c3e839be61"
    sha256 cellar: :any,                 arm64_big_sur:  "b6f4d442b6d2fcaf448d1af0c9b3810c411952fb6e070dffdce23fae741bc0ae"
    sha256 cellar: :any,                 monterey:       "e14a6b5f93a966a14ebd70615958f3d46421169a2782647e3b9932b64f3a6fd1"
    sha256 cellar: :any,                 big_sur:        "4d90068a7d02af344f2a809ff3e913b297b7990b9ccaf3df3f6f3d56d4962b4c"
    sha256 cellar: :any,                 catalina:       "3aca18a0ea3cb5b4728b79d4ddc3bbb2d2e2e617606f3a056119d57b20bec450"
    sha256 cellar: :any_skip_relocation, x86_64_linux:   "8b26f1923046f7c0bfce8c328dcff24add7a47482a2a40d0a3aabb30024bff4c"
  end

  depends_on "autoconf" => :build
  depends_on "autoconf-archive" => :build
  depends_on "automake" => :build
  # Use Erlang 24 to work around a sporadic build error with rebar (v2) and Erlang 25.
  # beam/beam_load.c(551): Error loading function rebar:save_options/2: op put_tuple u x:
  #   please re-compile this module with an Erlang/OTP 25 compiler
  # escript: exception error: undefined function rebar:main/1
  # Ref: https://github.com/Homebrew/homebrew-core/pull/105876
  depends_on "erlang@24" => :build
  depends_on "libtool" => :build
  depends_on "pkg-config" => :build
  depends_on "icu4c"
  depends_on "openssl@3"
  # NOTE: Supported `spidermonkey` versions are hardcoded at
  # https://github.com/apache/couchdb/blob/#{version}/src/couch/rebar.config.script
  depends_on "spidermonkey"

  on_linux do
    depends_on "gcc"
  end

  conflicts_with "ejabberd", because: "both install `jiffy` lib"

  fails_with :gcc do
    version "5"
    cause "mfbt (and Gecko) require at least gcc 6.1 to build."
  end

  def install
    spidermonkey = Formula["spidermonkey"]
    inreplace "src/couch/rebar.config.script" do |s|
      s.gsub! "-I/usr/local/include/mozjs", "-I#{spidermonkey.opt_include}/mozjs"
      s.gsub! "-L/usr/local/lib", "-L#{spidermonkey.opt_lib} -L#{HOMEBREW_PREFIX}/lib"
    end

    system "./configure", "--spidermonkey-version", spidermonkey.version.major
    system "make", "release"
    # setting new database dir
    inreplace "rel/couchdb/etc/default.ini", "./data", "#{var}/couchdb/data"
    # remove windows startup script
    rm_rf("rel/couchdb/bin/couchdb.cmd")
    # install files
    prefix.install Dir["rel/couchdb/*"]
    if File.exist?(prefix/"Library/LaunchDaemons/org.apache.couchdb.plist")
      (prefix/"Library/LaunchDaemons/org.apache.couchdb.plist").delete
    end
  end

  def post_install
    # creating database directory
    (var/"couchdb/data").mkpath
  end

  def caveats
    <<~EOS
      CouchDB 3.x requires a set admin password set before startup.
      Add one to your #{etc}/local.ini before starting CouchDB e.g.:
        [admins]
        admin = youradminpassword
    EOS
  end

  service do
    run opt_bin/"couchdb"
    keep_alive true
  end

  test do
    cp_r prefix/"etc", testpath
    port = free_port
    inreplace "#{testpath}/etc/default.ini", "port = 5984", "port = #{port}"
    inreplace "#{testpath}/etc/default.ini", "#{var}/couchdb/data", "#{testpath}/data"
    inreplace "#{testpath}/etc/local.ini", ";admin = mysecretpassword", "admin = mysecretpassword"

    fork do
      exec "#{bin}/couchdb -couch_ini #{testpath}/etc/default.ini #{testpath}/etc/local.ini"
    end
    sleep 30

    output = JSON.parse shell_output("curl --silent localhost:#{port}")
    assert_equal "Welcome", output["couchdb"]
  end
end
