use Documentable::Utils::IO;
use Documentable::Config;
use Documentable;
use URI::Escape;
use Pod::To::HTML;
use Template::Mustache;
use File::Temp;

unit class Documentable::To::HTML::Wrapper;

has Documentable::Config $.config;

has     &.rewrite;
has Str $.prefix;
has     %.prepopulated-templates;
has     $.mustache;

submethod BUILD(
    Documentable::Config :$!config,
) {
    $!prefix = '';
    &!rewrite = &rewrite-url;
    if ($!config.url-prefix) {
        $!prefix  = "/{$!config.url-prefix}";
        &!rewrite = &rewrite-url.assuming(*, $!config.url-prefix);
    }

    $!mustache = Template::Mustache.new;

    my @kinds-name = $!config.kinds.map({.<kind>});
    for @kinds-name -> $kind {
        self.prepopulate-template($kind);
    }
    self.prepopulate-template("default");
}

method prepopulate-template($kind) {
    my @menu    = self.generate-menu-entries($kind);
    my @submenu = self.generate-submenu-entries($kind);
    my ($filename, $filehandle) = tempfile;
    %!prepopulated-templates{$kind} = $filename;
    my $new-template = $!mustache.render(
        zef-path("template/main.mustache").IO.slurp,
        {
            :css(&!rewrite("/css/app.css")),
            :@menu,
            :@submenu,
            :$!prefix
        },
        :pragma<keep-unused-variables>
    );
    $new-template .= subst("toc-class", '{{^ toc }} no-toc{{/ toc }}');
    spurt $filename, $new-template;
}

method generate-menu-entries($selected) {
    my @menu-entries = $!config.kinds;
    @menu-entries .= map( -> $kind {
        %(
            class       => $selected eq $kind<kind> ?? "selected darker-green" !! "",
            href        => "$!prefix/$kind<kind>.html",
            display-text => $kind<display-text>
        )
    });

    my %irc-entry = %(
        class => '',
        href  =>  $!config.irc-link,
        display-text => "Chat with us"
    );

    @menu-entries.push(%irc-entry);
    return @menu-entries;
}

method generate-submenu-entries($selected) {
    # those kinds do not have submenus
    return () if $selected eq any("language", "programs", "default");
    my @submenuEntries = $!config.get-categories(Kind( $selected ));
    @submenuEntries .= map(-> $category {
        %(
            href         => "$!prefix/{$selected}-{$category<name>}.html",
            display-text => $category<display-text>
        )
    });

    my %all-entry = %(
        href => "$!prefix/$selected.html",
        display-text => "All"
    );
    return (%all-entry, slip @submenuEntries);
}

method generate-source-url($pod-path is copy) {
    my Regex $trailing-slash = /^\//;
    $pod-path .= subst($trailing-slash, '');
    return "{$.config.pod-root-path}/{$pod-path}";
}

method generate-edit-url($pod-path is copy) {
    $pod-path  = self.generate-source-url($pod-path);
    $pod-path .= subst('blob','edit');
}

method render($pod, $selected = '', :$pod-path = '') {
    my $source-url      = $pod-path && self.generate-source-url($pod-path);
    my $edit-source-url = $pod-path && self.generate-edit-url($pod-path);
    my $template = %!prepopulated-templates{$selected} || %!prepopulated-templates{"default"};
    render(
        $pod,
        url                => &!rewrite,
        editable           => $pod-path ?? '' !! 'none',
        editURL            => $edit-source-url,
        podPath            => self.generate-source-url($pod-path),
        main-template-path => $template
    )
}
