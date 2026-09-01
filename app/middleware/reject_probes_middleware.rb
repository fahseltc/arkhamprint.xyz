# Middleware that short-circuits common automated scanner probes before they
# reach the Rails router. Returns a bare 404 with no body — fast and cheap.
# This eliminates the RoutingError log noise from PHP webshell scanners,
# WordPress probes, and similar bots that hit every public-facing web server.
class RejectProbesMiddleware
  # Paths ending in .php will never exist on a Rails app.
  # Common WordPress/scanner path prefixes are also blocked.
  PHP_EXTENSION   = /\.php(\?.*)?$/i.freeze
  SCANNER_PREFIXES = %w[
    /wp-
    /wordpress
    /wp_
    /xmlrpc
    /phpmyadmin
    /pma/
    /admin/config
    /.env
    /shell
    /webshell
  ].freeze

  NOT_FOUND = [ 404, { "content-type" => "text/plain", "content-length" => "0" }, [] ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    path = env["PATH_INFO"].to_s
    return NOT_FOUND if PHP_EXTENSION.match?(path)
    return NOT_FOUND if SCANNER_PREFIXES.any? { |prefix| path.start_with?(prefix) }
    @app.call(env)
  end
end
