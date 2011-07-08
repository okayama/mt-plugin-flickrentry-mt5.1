package MT::Plugin::FlickrEntry;
use strict;
use MT;
use MT::Plugin;
use base qw( MT::Plugin );
use MT::Util qw( encode_html );

our $PLUGIN_NAME = 'FlickrEntry';
our $PLUGIN_VERSION = '1.0';
our $SCHEMA_VERSION = '1.3';

my $plugin = new MT::Plugin::FlickrEntry( {
    id => $PLUGIN_NAME,
    key => lc $PLUGIN_NAME,
    name => $PLUGIN_NAME,
    version => $PLUGIN_VERSION,
    schema_version => $SCHEMA_VERSION,
    description => "<MT_TRANS phrase='Utility for creating entry from flickr.'>",
    author_name => 'okayama',
    author_link => 'http://weeeblog.net/',
    l10n_class => 'MT::' . $PLUGIN_NAME . '::L10N',
	blog_config_template => \&_blog_config_template,
    settings => new MT::PluginSettings( [
        [ 'is_active', { Default => '', Scope => 'blog' } ],
    ] ),
} );
MT->add_plugin( $plugin );

sub init_registry {
    my $plugin = shift;
    $plugin->registry( {
        object_types => {
            entry => {
                photo_id => 'string(255)',
                photo_url => 'string(255)',
                photo_page_url => 'string(255)',
                photo_thumbnail_url => 'string(255)',
                photo_description => 'string(255)',
            },
        },
        callbacks => {
            'MT::App::CMS::template_param.edit_entry' => 'MT::' . $PLUGIN_NAME . '::Plugin::_cb_tp_edit_entry',
        },
        tags => {
            function => {
                EntryPhotoID => 'MT::' . $PLUGIN_NAME . '::Tags::_hdlr_entry_photo_id',
                EntryPhotoURL => 'MT::' . $PLUGIN_NAME . '::Tags::_hdlr_entry_photo_url',
                EntryPhotoPageURL => 'MT::' . $PLUGIN_NAME . '::Tags::_hdlr_entry_photo_page_url',
                EntryPhotoThumbnailURL => 'MT::' . $PLUGIN_NAME . '::Tags::_hdlr_entry_photo_thumbnail_url',
                EntryPhotoDescription => 'MT::' . $PLUGIN_NAME . '::Tags::_hdlr_entry_photo_description',
            },
        },
        tasks => {
            check_flickr_photo_url => {
                label => 'FlickrEntry Task',
                frequency => 5,
                code => \&check_flickr_photo_url,
            },
        },
    } );
}

sub check_flickr_photo_url {
    my @blogs = MT::Blog->load( { class => '*' } );
    for my $blog ( @blogs ) {
        my $blog_id = $blog->id;
        my $scope = 'blog:' . $blog_id;
        next unless $plugin->get_config_value( 'is_active', $scope );
        my @entries = MT::Entry->load( { blog_id => $blog_id,
                                         class => '*',
                                       }
                                     );
        for my $entry ( @entries ) {
            my $check = 0;
            my $ua = MT->new_ua;
            if ( my $photo_url = $entry->photo_url ) {
                my $req = HTTP::Request->new( GET => $photo_url );
                $req->header( 'User-Agent' => "$PLUGIN_NAME/$PLUGIN_VERSION" );
                my $res = $ua->simple_request( $req ) or return;
                unless ( $res->is_success ) {
                    $check++;
                }
            }
            if ( my $photo_thumbnail_url = $entry->photo_thumbnail_url ) {
                my $req = HTTP::Request->new( GET => $photo_thumbnail_url );
                $req->header( 'User-Agent' => "$PLUGIN_NAME/$PLUGIN_VERSION" );
                my $res = $ua->simple_request( $req ) or return;
                unless ( $res->is_success ) {
                    $check++;
                }
            }
            if ( $check ) {
                if ( my $photo_page_url = $entry->photo_page_url ) {
                    my $req = HTTP::Request->new( GET => $photo_page_url ) or return;
                    $req->header( 'User-Agent' => "$PLUGIN_NAME/$PLUGIN_VERSION" );
                    my $res = $ua->request( $req ) or return;
                    if ( $res->is_success ) {
                        my $content = $res->decoded_content;
                        my $tree = HTML::TreeBuilder->new;
                        $tree->parse( $content );                        
                        for my $meta ( $tree->find( 'link' ) ) {
                            my $rel = $meta->attr( 'rel' );
                            my $href;
                            if ( $rel && $rel eq 'image_src' ) {
                                $href = $meta->attr( 'href' );
                            }
                            if ( $href ) {
                                my $photo_url = $href;
                                $photo_url =~ s/_m/_z/;
                                $entry->photo_url( $photo_url );
                                my $photo_thumbnail_url = $href;
                                $photo_thumbnail_url =~ s/_m/_s/;
                                $entry->photo_thumbnail_url( $photo_thumbnail_url );
                                $entry->save or die $entry->errstr;
                                my $message = $plugin->translate( 'Updated link entry \'[_1]\'', encode_html( $entry->title ) );
                                MT->log( { message => $message,
                                           blog_id => $entry->blog_id,
                                         }
                                       );
                                MT->rebuild_entry( Entry => $entry );
                                last;
                            }
                        }
                    }
                }
            }
        }
    }
}

sub _blog_config_template {
	my $plugin = shift;
	my ( $param,  $scope ) = @_;
	my $tmpl = $plugin->load_tmpl( lc $PLUGIN_NAME . '_config_blog.tmpl' );
	my $blog_id = $scope;
	$blog_id =~ s/blog://;
	$tmpl->param( 'blog_id' => $blog_id );
	my $app = MT->instance;
	$tmpl->param( 'mt_url' => $app->base . $app->uri );
	return $tmpl; 
}

1;
