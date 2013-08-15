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
    return $app->redirect( $app->mt_uri . '?__mode=dashboard&blog_id=0' )
        unless $blog_id;

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
        $app->{cfg}->CGIPath . $app->{cfg}->AdminScript
        . "?__mode=publishing_priorities.edit&blog_id=" . $blog_id . "&saved=1"
    );
}

# List/edit the publishing priorities for a blog. (System level settings)
sub system_edit {
    my $app     = shift;
    my $q       = $app->can('query') ? $app->query : $app->param;
    my $plugin  = $app->component('PublishingPriorities');
    my $param   = {};

    $param->{saved} = $q->param('saved');

    # MT5 should return both websites and blogs, while MT4 returns blogs only.
    my $terms = {};
    my @args_sort;
    if ($app->product_version =~ /^5/) {
        $terms->{class} = '*'; # Blogs and websites
        push @args_sort, {     # Sort the website first, then blogs.
            column => 'class',
            desc   => 'DESC',
        };
    }
    
    # Sort blogs by name in MT4 and MT5. In MT5, this sorts blogs after
    # websites.
    push @args_sort, { column => 'name' };

    my $iter = $app->model('blog')->load_iter(
        $terms,
        { sort => \@args_sort, }
    );

    my @blogs;
    while ( my $blog = $iter->() ) {
        # Check if this blog has any templates set to use the Publish queue.
        # If there are any, add this blog to the @blogs array to be available
        # for editing.
        if (
            # Check if any index templates use the PQ
            $app->model('template')->exist({
                blog_id    => $blog->id,
                type       => 'index',
                build_type => MT::PublishOption::ASYNC(),
            })
            # Check for any archive templates set to use the PQ
            || $app->model('templatemap')->exist({
                blog_id    => $blog->id,
                build_type => MT::PublishOption::ASYNC(),
            })
        ) {
            push @blogs, {
                id       => $blog->id,
                name     => $blog->name,
                desc     => $blog->description,
                class    => $blog->has_column('class') ? $blog->class : 'blog',
                priority => $plugin->blog_priority( $blog->id ),
            };
        }
    }
    $param->{blog_loop} = \@blogs;

    return $plugin->load_tmpl('system_edit.tmpl', $param);
}

# Save the system-level publishing priorities overview.
sub system_save {
    my $app     = shift;
    my $q       = $app->can('query') ? $app->query : $app->param;
    my $bids    = $q->param('blog_ids');
    my $plugin  = $app->component('PublishingPriorities');

    # The `blog_ids` parameter contains array of ids being edited (CSV)
    if ( $bids ) {
        $plugin->blog_priority(
            map {  $_ => $q->param('blog-'.$_) } split( ',', $bids )
        );
    }

    # Redirect back to the Edit screen.
    $app->redirect(
        $app->{cfg}->CGIPath . $app->{cfg}->AdminScript
        . "?__mode=publishing_priorities.system_edit&blog_id=0&saved=1"
    );
}

1;

