package MT::Plugin::PublishingPriorities;

use strict;
use warnings;
use v5.10.1;

use parent qw( MT::Plugin );

use MT::PublishOption;
use MT::Logger::Log4perl qw( get_logger l4mtdump :resurrect );
use Data::Printer {
    colored      => 'auto',
    deparse      => 1,
    sort_keys    => 1,
    return_value => 'dump',
    caller_info  => 1,
    output       => 'stderr',
    class        => {
            expand => 2,
	},
};

sub load_async_templates {
    my ($self, $blog_id ) = @_;
    my $app               = MT->instance;
    my $config            = $self->get_config_hash('system');
    my $priorities        = $config->{template_priorities} || {};

    my @tmpls;
    my %tmpl_load_args = (
        blog_id    => $blog_id,
        build_type => MT::PublishOption::ASYNC(),
    );

    # Load index templates configured to use the Publish Queue.
    my $iter = $app->model('template')->load_iter(
        { %tmpl_load_args, type => 'index' },
        { sort => [ { column => 'type', desc => 'DESC'},
                    { column => 'name', } ] }
    );

    while ( my $tmpl = $iter->() ) {
        push @tmpls, {
            id       => $tmpl->id,
            name     => $tmpl->name,
            type     => 'Index',
            out      => $tmpl->outfile,
            priority => (    $priorities->{ $tmpl->id }
                          // $self->_set_default_priority({ tmpl => $tmpl })),
        };
    }
    
    # Load archive templates configured to use the Publish Queue.
    $iter = $app->model('templatemap')->load_iter(
        \%tmpl_load_args,
        { sort => [ { column => 'archive_type', },
                    { column => 'is_preferred', desc => 'DESC' } ] }
    );

    while ( my $tmpl_map = $iter->() ) {
        my $tmpl = $app->model('template')->load( $tmpl_map->template_id )
            or next;

        # Template ID and template map ID are combined to create a
        # unique identifier.
        my $key = $tmpl->id . ':' . $tmpl_map->id;

        push @tmpls, {
            id           => $key,
            name         => $tmpl->name,
            type         => $tmpl_map->archive_type,
            out          => $tmpl_map->file_template,
            is_preferred => $tmpl_map->is_preferred,
            priority     => (    $priorities->{ $key }
                              // $self->_set_default_priority({
                                    tmpl => $tmpl, tmpl_map => $tmpl_map }) ),
        };
    }

    return \@tmpls;
}

# These priorities come from Movable Type, and are the default values used by
# it. They're a reasonable starting point and will provide some expected
# behavior, so we'll stick with them.
sub _set_default_priority {
    my $self      = shift;
    my ($arg_ref) = @_;
    my $tmpl      = $arg_ref->{tmpl};
    my $tmpl_map  = $arg_ref->{tmpl_map};
    my $app       = MT->instance;
    my $priority  = 1;

    # First handle the Index Templates because they don't use a templatemap.
    if ( $tmpl->type eq 'index' ) {
        # Fix a bug in the below regex, which also exists in MT that would
        # cause all templates to get a priority 8.
        # if ( $tmpl->outfile =~ m!/(index|default|atom|feed)!i ) {
        if ( $tmpl->outfile =~ m!(index|default|atom|feed)!i ) {
            $priority = 9;
        }
        else {
            $priority = 8;
        }
        return $priority;
    }

    # Use the archive type to determine the type of template being published
    my $at = $tmpl_map->archive_type || '';

    if ( ( $at eq 'Individual' ) || ( $at eq 'Page' ) ) {
        # Individual/Page archive pages that are the 'permalink' pages
        # should have highest build priority.
        if ( $tmpl_map->is_preferred ) {
            $priority = 10;
        }
        else {
            $priority = 5;
        }
    }
    elsif ( $at =~ m/Category|Author/ ) {
        $priority = 1;
    }
    elsif ( $at =~ m/Yearly/ ) {
        $priority = 1;
    }
    elsif ( $at =~ m/Monthly/ ) {
        $priority = 2;
    }
    elsif ( $at =~ m/Weekly/ ) {
        $priority = 3;
    }
    elsif ( $at =~ m/Daily/ ) {
        $priority = 4;
    }

    return $priority;
}

# The Publishing Prioritis callback runs before the default (in
# MT::WeblogPublisher::queue_build_file_filter_callback), effectively taking
# over sending to the Publish Queue in order to set user-specified priorities.
sub callback_build_file_filter {
    my ( $cb, %args ) = @_;
    my $fi        = $args{file_info};
    my $throttle  = MT::PublishOption::get_throttle($fi);
    my $not_async = $throttle->{type} != MT::PublishOption::ASYNC() ? 1 : 0;
    my $forced    = $args{force} ? 1 : 0;

    return 1 if $fi->{from_queue};  # Async pub process. Don't requeue/report

    if ( $forced || $not_async ) {
        ###l4p get_logger()->debug(
        ###l4p     join( ' ', 'PASS:', $fi->url,
        ###l4p                ( $forced    ? 'FORCED'    : () ),
        ###l4p                ( $not_async ? 'NOT ASYNC' : () )  )
        ###l4p );
        return 1;
    }

    require MT::TheSchwartz;
    require TheSchwartz::Job;
    my $job = TheSchwartz::Job->new();
    $job->funcname('MT::Worker::Publish');
    $job->uniqkey( $fi->id );

    # Look at the fileinfo record's template ID and template map ID to
    # determine how to prioritize this file.
    my $id = $fi->template_id;
    $id .= ':' . $fi->templatemap_id
        if defined $fi->templatemap_id;

    # Priorities are saved in the plugin settings.
    my $plugin = MT->component('PublishingPriorities');
    my $config = $plugin->get_config_hash('system');
    my $blog_priorities = $config->{blog_priorities};
    my $tmpl_priorities = $config->{template_priorities};

    # Set the template priority based on the saved value. If no saved value
    # exists then fall back to the default values.
    my $priority = 0;
    if ( $tmpl_priorities->{ $id } ) {
        $priority = $tmpl_priorities->{ $id };
    }
    else {
        ###l4p get_logger->debug( 'Publishing Priorities could not find a '
        ###l4p                  . 'saved priority for this template; using '
        ###l4p                  .'a default. ID: '.$id );
        my $tmpl = MT->model('template')->load( $fi->template_id );
        my $tmpl_map = MT->model('templatemap')->load( $fi->templatemap_id )
            ||  {};

        my $plugin = MT->instance->component('PublishingPriorities');
        $priority  = $plugin->_set_default_priority({
            tmpl     => $tmpl,
            tmpl_map => $tmpl_map,
        });
    }

    # Apply the blog priority adjustment. By default there is no change to
    # priority and all blogs are weighted equally.
    $priority += $blog_priorities->{ $fi->blog_id } || '0';

    # FIXME This will be a problem if a template is already on the queue with a lower priority
    # We should instead try to load the job, adjusting the priority if found
    # Otherwise, then create it
    $job->priority($priority);
    $job->coalesce( ( $fi->blog_id || 0 ) . ':' 
            . $$ . ':'
            . $priority . ':'
            . ( time - ( time % 10 ) ) );

    my $rv = MT::TheSchwartz->insert($job);
    ###l4p $rv && get_logger->info('Publishing job inserted for '.$fi->url);

    return 0;
}

1;

__END__

build_file_filter callback args:

    For indexes:
        %args = (
            archive_type => 'index',
            blog         => $blog,
            context      => $ctx,
            file         => $file,
            file_info    => $finfo,
            force        => $force,
            template     => $tmpl,
        )

    For archives
        %args = (
            archive_type => $at,
            blog         => $blog,
            category     => $category,
            context      => $ctx,
            entry        => $entry,
            file         => $file,
            file_info    => $finfo,
            force        => $force,
            period_start => $start,
            template     => $tmpl,
            template_map => $map,
        )
