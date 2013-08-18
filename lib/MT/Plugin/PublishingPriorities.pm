package MT::Plugin::PublishingPriorities;

=head1 NAME

MT::Plugin::PublishingPriorities

=head1 DESCRIPTION

Plugin class for the Publishing Priorities plugin.

=cut
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

=head1 CALLBACK HANDLERS

=head2 callback_build_file_filter

This replaces MT::WeblogPublisher::queue_build_file_filter_callback in order
to set user-specified priorities.

=cut
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

    my $plugin = MT->component('PublishingPriorities');
    my $priority = $plugin->template_priority( $id ) || 0;
    unless ( $priority ) {
        my $tmpl     = MT->model('template')->load( $fi->template_id );
        my $tmpl_map
            = MT->model('templatemap')->load( $fi->templatemap_id ) ||  {};

        $priority  = $plugin->_set_default_priority({
            tmpl     => $tmpl,
            tmpl_map => $tmpl_map,
        });
    }

    # Apply the blog priority adjustment. By default there is no change to
    # priority and all blogs are weighted equally.
    $priority += $plugin->blog_priority( $fi->blog_id ) || '0';

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

=head1 INSTANCE METHODS

=head2 blog_priority( $blog_id[, $priority ] )

=head2 blog_priority( \%priorities )

This plugin instance method is used for getting or setting one or more blog
priorities:

    my $plugin = $app->component('PublishingPriorities');
    $plugin->blog_priority( $blog_id );            # Gets priority for $blog_id
    $plugin->blog_priority( $blog_id, $priority ); # Sets priority for $blog_id
    $plugin->blog_priority( \%blog_priorities );   # Sets priority for many
                                                   #  blogs ( ID => PRI, ID => PRI )
=cut
sub blog_priority     { shift->_priorities( 'blog',     @_ ) }

=head2 template_priority( $tmpl_id[, $priority ] )

=head2 template_priority( \%priorities )

This plugin instance method is used for getting or setting one or more template
priorities.  Syntax mirrors that of the L<blog_priority> method.

=cut
sub template_priority { shift->_priorities( 'template', @_ ) }

sub _priorities {
    my ( $self, $type, $id, $pri ) = @_;
    my $priorities
        = $self->get_config_value("${type}_priorities",'system') || {};

    # Single argument, hash reference: Set multiple
    if ( ref $id eq 'HASH' ) {
        $priorities->{$_} = $id->{$_} for keys %$id;
        $self->set_config_value('${type}_priorities', $priorities);
        return $id;
    }

    # One or two arguments: Get or set individual
    if ( defined $pri ) {
        $priorities->{$id} = $pri;
        $self->set_config_value('${type}_priorities', $priorities);
    }
    return $priorities->{$id};
}

=head2 load_async_blogs()

=cut
sub load_async_blogs {
    my $self = shift;
    my $app  = MT->instance;

    # Default blog load terms/sort args. Fine for MT 4.
    my ( $terms, $args ) = ( {}, { sort => [ { column => 'name' } ] } );

    # But MT 5 needs some tweaks...
    if ( $app->product_version =~ /^5/ ) {
        $terms->{class} = '*';          # Return blogs *and* websites
        unshift @{ $args->{sort} }, {   # Sort the website first, then blogs.
            column => 'class',
            desc   => 'DESC',
        };
    }

    my $iter = $app->model('blog')->load_iter( $terms, $args );

    my @blogs;
    while ( my $blog = $iter->() ) {
        push( @blogs, $blog ) if $self->blog_uses_async($blog);
    }

    return \@blogs;
}

=head2 blog_uses_async

A filtering/extraction subref which checks if a specified blog's index
or archive templates use the Publish Queue and, if so, returns 
pertinent info about the blog.

=cut
sub blog_uses_async {
    my ( $self, $blog ) = @_;
    my $app             = MT->instance;
    my %pq_args         = ( blog_id    => $blog->id,
                            build_type => MT::PublishOption::ASYNC() );
    return ( # boolean
           $app->model('template')->exist(    { %pq_args, type => 'index'} )
        || $app->model('templatemap')->exist( \%pq_args )
    );
}


=head2 load_async_templates( $blog_id )

Plugin instance method used to retrieve all index and archive templates for
a particular blog which are configured to be published using the Publish Queue.

=cut
sub load_async_templates {
    my ( $self, $blog_id ) = @_;

    my $terms = {   blog_id    => $blog_id,
                    build_type => MT::PublishOption::ASYNC() };

    return [
        @{ $self->_load_async_index_templates($terms)   },
        @{ $self->_load_async_templatemaps($terms) },
    ];
}

sub _load_async_index_templates {
    my ( $self, $terms ) = @_;
    my $app              = MT->instance;

    # Load index templates configured to use the Publish Queue.
    my $iter = $app->model('template')->load_iter(
        { %$terms, type => 'index' },
        { sort => [ { column => 'type', desc => 'DESC'},
                    { column => 'name', } ] }
    );

    my @tmpls;
    while ( my $tmpl = $iter->() ) {
        push( @tmpls, $tmpl );
    }
    return \@tmpls;
}

sub _load_async_templatemaps {
    my ( $self, $terms ) = @_;
    my $app                = MT->instance;

    # Load archive templates configured to use the Publish Queue.
    my $iter = $app->model('templatemap')->load_iter(
        $terms,
        { sort => [ { column => 'archive_type', },
                    { column => 'is_preferred', desc => 'DESC' } ] }
    );

    my @tmpls;
    while ( my $tmpl_map = $iter->() ) {
        push( @tmpls, $tmpl_map );
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
