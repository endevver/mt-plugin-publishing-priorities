package MT::Plugin::PublishingPriorities::CMS;

use strict;
use warnings;

use MT::PublishOption;

# List/edit the publishing priorities for a blog.
sub edit {
    my $app     = shift;
    my $q       = $app->can('query') ? $app->query : $app->param;
    my $plugin  = $app->component('PublishingPriorities');
    my $param   = {};
    my $blog_id = $q->param('blog_id');
    my @tmpls;

    # No blog was found, so this must be the system level. Just go to the
    # System Dashboard.
    if (!$blog_id) {
        return $app->redirect( $app->mt_uri . '?__mode=dashboard&blog_id=0' );
    }

    $param->{blog_id}    = $blog_id;
    $param->{saved}      = $q->param('saved');
    # MT5 Has both Blogs and Websites, while MT4 just has blogs. Create the
    # appropriate label.
    $param->{blog_class} = ($app->blog && $app->product_version =~ /^5/)
        ? $app->blog->class
        : 'blog';

    # Priorities are saved in the plugin settings.
    my $config  = $plugin->get_config_hash('system');
    my $blog_priorities = $config->{blog_priorities};
    my $tmpl_priorities = $config->{template_priorities};

    # Get the blog priority, which is a gross adjustment of priority.
    $param->{blog_priority} = $blog_priorities->{ $blog_id };

    # Only load index templates, and only load those set to use the
    # Publish Queue.
    my $iter = $app->model('template')->load_iter(
        {
            blog_id    => $blog_id,
            type       => 'index',
            build_type => MT::PublishOption::ASYNC(),
        },
        {
            sort => [
                { column => 'type', desc => 'DESC'},
                { column => 'name', },
            ],
        }
    );

    while ( my $tmpl = $iter->() ) {
        # Get the priority for this template. Use the saved priority, or fall
        # back to the default priorities.
        my $priority;
        if ( $tmpl_priorities->{ $tmpl->id } ) {
            $priority = $tmpl_priorities->{ $tmpl->id };
        }
        else {
            $priority = $plugin->_set_default_priority({ tmpl => $tmpl });
        }

        push @tmpls, {
            id       => $tmpl->id,
            name     => $tmpl->name,
            type     => 'Index',
            priority => $priority,
            out      => $tmpl->outfile,
        };
    }

    # Only load archive templates, and only load those set to use the
    # Publish Queue.
    $iter = $app->model('templatemap')->load_iter(
        {
            blog_id    => $blog_id,
            build_type => MT::PublishOption::ASYNC(),
        },
        {
            sort => [
                { column => 'archive_type', },
                { column => 'is_preferred', desc => 'DESC' },
            ],
        }
    );

    while ( my $tmpl_map = $iter->() ) {
        my $tmpl = $app->model('template')->load( $tmpl_map->template_id )
            or next;

        # Get the priority for this template. Use the saved priority, or fall
        # back to the default priorities.
        my $priority;
        if ( $tmpl_priorities->{ $tmpl->id . ':' . $tmpl_map->id } ) {
            $priority = $tmpl_priorities->{ $tmpl->id . ':' . $tmpl_map->id };
        }
        else {
            $priority = $plugin->_set_default_priority({
                tmpl     => $tmpl,
                tmpl_map => $tmpl_map,
            });
        }

        # Note how the template ID and template map ID are combined to create a
        # unique identifier.
        push @tmpls, {
            id           => $tmpl->id . ':' . $tmpl_map->id,
            name         => $tmpl->name,
            type         => $tmpl_map->archive_type,
            priority     => $priority,
            out          => $tmpl_map->file_template,
            is_preferred => $tmpl_map->is_preferred,
        };
    }

    $param->{tmpl_loop} = \@tmpls;

    return $plugin->load_tmpl('edit.tmpl', $param);
}

# Save the template publishing priorities
sub save {
    my $app     = shift;
    my $q       = $app->can('query') ? $app->query : $app->param;
    my $blog_id = $q->param('blog_id');
    my $plugin  = $app->component('PublishingPriorities');

    my $blog_priorities
        = $plugin->get_config_value('blog_priorities', 'system');
    my $tmpl_priorities
        = $plugin->get_config_value('template_priorities', 'system');

    # Set the blog priority.
    $blog_priorities->{ $blog_id } = $q->param("blog_priority");
    $plugin->set_config_value('blog_priorities', $blog_priorities);

    # The `tmpl_ids` query parameter contains the ids of all templates being
    # edited.
    my @tmpl_ids = split( ',', $q->param('tmpl_ids') );
    foreach my $tmpl_id (@tmpl_ids) {
        $tmpl_priorities->{ $tmpl_id } = $q->param('tmpl-'.$tmpl_id);
    }

    $plugin->set_config_value('template_priorities', $tmpl_priorities);
    
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

    # Priorities are saved in the plugin settings.
    my $config  = $plugin->get_config_hash('system');
    my $blog_priorities = $config->{blog_priorities};

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
                priority => $blog_priorities->{ $blog->id },
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
    my $plugin  = $app->component('PublishingPriorities');

    my $blog_priorities
        = $plugin->get_config_value('blog_priorities', 'system');

    # The `blog_ids` query parameter contains the ids of all blogs/websites
    # being edited.
    my @blog_ids = split( ',', $q->param('blog_ids') );
    foreach my $blog_id (@blog_ids) {
        $blog_priorities->{ $blog_id } = $q->param('blog-'.$blog_id);
    }

    $plugin->set_config_value('blog_priorities', $blog_priorities);

    # Redirect back to the Edit screen.
    $app->redirect(
        $app->{cfg}->CGIPath . $app->{cfg}->AdminScript
        . "?__mode=publishing_priorities.system_edit&blog_id=0&saved=1"
    );
}

1;
