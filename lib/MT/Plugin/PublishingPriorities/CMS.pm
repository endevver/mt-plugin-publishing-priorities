package MT::Plugin::PublishingPriorities::CMS;

use strict;
use warnings;

use MT::PublishOption;

# List/edit the publishing priorities for a blog.
sub edit {
    my $app     = shift;
    my $q       = $app->can('query') ? $app->query : $app->param;
    my $plugin  = $app->component('PublishingPriorities');
    my $blog_id = int($q->param('blog_id'));

    # No blog was found, so this must be the system level. Just go to the
    # System Dashboard.
    unless ( $blog_id ) {
        return $app->redirect(
            $app->uri( mode => 'dashboard', args => { blog_id => 0 } ) );
    }

    my $param   = {
        blog_class    => 'blog',
        blog_id       => $blog_id,
        tmpl_loop     => ($plugin->load_async_templates( $blog_id ) || []),
        # blog priority is a gross adjustment of priority.
        blog_priority => $plugin->blog_priority( $blog_id ),
    };

    # Update blog_class for MT5 if appropriate (has both Blogs and Websites)
    $param->{blog_class} = $app->blog->class
        if $app->blog && $app->product_version =~ /^5/;

    $param->{saved} = $q->param('saved') if $q->param('saved');

    return $plugin->load_tmpl('edit.tmpl', $param);
}

# Save the template publishing priorities
sub save {
    my $app      = shift;
    my $q        = $app->can('query') ? $app->query : $app->param;
    my $blog_id  = $q->param('blog_id');
    my $blog_pri = $q->param('blog_priority');
    my $tmpls    = $q->param('tmpl_ids');
    my $plugin   = $app->component('PublishingPriorities');

    # Set the blog priority.
    $plugin->blog_priority( $blog_id, $blog_pri ) if $blog_pri;

    # The `tmpl_ids` parameter contains array of ids being edited (CSV)
    if ( $tmpls ) {
        $plugin->template_priority(
            map {  $_ => $q->param('tmpl-'.$_) } split( ',', $tmpls )
        );
    }

    # Redirect back to the Edit screen.
    $app->redirect(
        $app->uri( mode => 'publishing_priorities.edit',
                   args    => { blog_id => $blog_id, saved => 1 } )
    );
}

# List/edit the publishing priorities for a blog. (System level settings)
sub system_edit {
    my $app    = shift;
    my $q      = $app->can('query') ? $app->query : $app->param;
    my $saved  = $q->param('saved');
    my $plugin = $app->component('PublishingPriorities');
    my @async  = map {
        {
            id       => $_->id,
            name     => $_->name,
            desc     => $_->description,
            priority => $plugin->blog_priority( $_->id ),
            class    => $_->has_column('class') ? $_->class : 'blog',
        }
      } @{ $plugin->load_async_blogs() };

    return $plugin->load_tmpl('system_edit.tmpl', {
        blog_loop => \@async,
        $saved ? ( saved => $saved ) : ()
    });
}

# Save the system-level publishing priorities overview.
sub system_save {
    my $app     = shift;
    my $q       = $app->can('query') ? $app->query : $app->param;
    my $plugin  = $app->component('PublishingPriorities');

    # The `blog_ids` parameter contains array of ids being edited (CSV)
    if ( my $bids = $q->param('blog_ids') ) {
        $plugin->blog_priority(
            map {  $_ => $q->param('blog-'.$_) } split( ',', $bids )
        );
    }

    # Redirect back to the Edit screen.
    $app->redirect(
        $app->uri( mode => 'publishing_priorities.edit',
                   args    => { blog_id => 0, saved => 1 } )
    );
}

1;

