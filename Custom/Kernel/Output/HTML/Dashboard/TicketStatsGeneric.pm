# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::Dashboard::TicketStatsGeneric;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # get needed parameters
    for my $Needed (qw(Config Name UserID)) {
        die "Got no $Needed!" if !$Self->{$Needed};
    }

    return $Self;
}

sub Preferences {
    my ( $Self, %Param ) = @_;

    return;
}

sub Config {
    my ( $Self, %Param ) = @_;

    return (
        %{ $Self->{Config} },

        # Don't cache this globally as it contains JS that is not inside of the HTML.
        CacheTTL => undef,
        CacheKey => undef,
    );
}

sub Run {
    my ( $Self, %Param ) = @_;

# ---
# PS
# ---
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
# ---

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    my $Key      = $LayoutObject->{UserLanguage} . '-' . $Self->{Name};
    my $CacheKey = 'TicketStats' . '-' . $Self->{UserID} . '-' . $Key;

    my $Cache = $Kernel::OM->Get('Kernel::System::Cache')->Get(
        Type => 'Dashboard',
        Key  => $CacheKey,
    );

    if ( ref $Cache ) {
        return $LayoutObject->Output(
            TemplateFile   => 'AgentDashboardTicketStats',
            Data           => $Cache,
            KeepScriptTags => $Param{AJAX},
        );
    }

    my %Axis = (
        '7Day' => {
            0 => 'Sun',
            1 => 'Mon',
            2 => 'Tue',
            3 => 'Wed',
            4 => 'Thu',
            5 => 'Fri',
            6 => 'Sat',
        },
    );

    my $ClosedText      = $LayoutObject->{LanguageObject}->Translate('Closed');
    my $CreatedText     = $LayoutObject->{LanguageObject}->Translate('Created');
    my $StateText       = $LayoutObject->{LanguageObject}->Translate('State');
    my @TicketsCreated  = ();
    my @TicketsClosed   = ();
    my @TicketWeekdays  = ();
    my $Max             = 0;
    my $UseUserTimeZone = 0;

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # get the time object
    my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

    # use the UserTimeObject, if the system use UTC as system time and the TimeZoneUser feature is active
    if (
        !$Kernel::OM->Get('Kernel::System::Time')->ServerLocalTimeOffsetSeconds()
        && $Kernel::OM->Get('Kernel::Config')->Get('TimeZoneUser')
        && $Self->{UserTimeZone}
        )
    {
        $UseUserTimeZone = 1;
        $TimeObject      = $LayoutObject->{UserTimeObject};
    }

# ---
# PS
# ---
    my @ShownStats;
    my %StatIndexes;

    my %Stats = %{ $ConfigObject->Get( 'GenericDashboardStats::Stats' ) || {} };

    for my $Stat ( sort keys %Stats ) {
        my $Key         = $Stats{$Stat}->{OptionKey};
        my $StatsConfig = $ConfigObject->Get( $Key ) || {};

        $Stats{$Stat}->{SearchOptions} = $StatsConfig;

        my $Label = $Stats{$Stat}->{label} || $Stat;
        $Stats{$Stat}->{label} = $LayoutObject->{LanguageObject}->Translate( $Label );

        push @ShownStats, [ $Stats{$Stat}->{label} ];
        $StatIndexes{$Stat} = $#ShownStats;
    }

    my $Days = $ConfigObject->Get('GenericDashboardStats::Days') || 14;

#    for my $Key ( 0 .. 6 ) {
    for my $Key ( 0 .. $Days-1 ) {
# ---

        # get the system time
        my $TimeNow = $TimeObject->SystemTime();

        # cache results for 30 min. for todays stats
        my $CacheTTL = 60 * 30;

        if ($Key) {
            $TimeNow = $TimeNow - ( 60 * 60 * 24 * $Key );

            # for past 6 days cache results for 8 days (should not change)
            $CacheTTL = 60 * 60 * 24 * 8;
        }
        my ( $Sec, $Min, $Hour, $Day, $Month, $Year, $WeekDay ) = $TimeObject->SystemTime2Date(
            SystemTime => $TimeNow,
        );

        unshift(
            @TicketWeekdays,
            $LayoutObject->{LanguageObject}->Translate( $Axis{'7Day'}->{$WeekDay} )
        );

        my $TimeStart = "$Year-$Month-$Day 00:00:00";
        my $TimeStop  = "$Year-$Month-$Day 23:59:59";

        if ($UseUserTimeZone) {

            my $SystemTimeStart = $TimeObject->TimeStamp2SystemTime(
                String => $TimeStart,
            );
            my $SystemTimeStop = $TimeObject->TimeStamp2SystemTime(
                String => $TimeStop,
            );

            $SystemTimeStart = $SystemTimeStart - ( $Self->{UserTimeZone} * 3600 );
            $SystemTimeStop  = $SystemTimeStop -  ( $Self->{UserTimeZone} * 3600 );

            $TimeStart = $TimeObject->SystemTime2TimeStamp(
                SystemTime => $SystemTimeStart,
            );
            $TimeStop = $TimeObject->SystemTime2TimeStamp(
                SystemTime => $SystemTimeStop,
            );
        }
# ---
# PS
# ---

        for my $Stat ( sort keys %Stats ) {
            my %Options = (
                $Stats{$Stat}->{type} . 'TimeNewerDate' => $TimeStart,
                $Stats{$Stat}->{type} . 'TimeOlderDate' => $TimeStop,
                %{ $Stats{$Stat}->{SearchOptions} },
            );

            my $Count = $TicketObject->TicketSearch(
                %Options,

                # cache search result 30 min
                CacheTTL => 60 * 30,

                CustomerID => $Param{Data}->{UserCustomerID},
                Result     => 'COUNT',

                # search with user permissions
                Permission => $Self->{Config}->{Permission} || 'ro',
                UserID => $Self->{UserID},
            );

            if ( $Count && $Count > $Max ) {
                $Max = $Count;
            }

            my $Index = $StatIndexes{$Stat};
            splice @{ $ShownStats[$Index] }, 1, 0,$Count;
        }
# ---

=pod

        my $CountCreated = $TicketObject->TicketSearch(

            # cache search result
            CacheTTL => $CacheTTL,

            # tickets with create time after ... (ticket newer than this date) (optional)
            TicketCreateTimeNewerDate => $TimeStart,

            # tickets with created time before ... (ticket older than this date) (optional)
            TicketCreateTimeOlderDate => $TimeStop,

            CustomerID => $Param{Data}->{UserCustomerID},
            Result     => 'COUNT',

            # search with user permissions
            Permission => $Self->{Config}->{Permission} || 'ro',
            UserID => $Self->{UserID},
        );
        if ( $CountCreated && $CountCreated > $Max ) {
            $Max = $CountCreated;
        }
        push @TicketsCreated, $CountCreated;

        my $CountClosed = $TicketObject->TicketSearch(

            # cache search result
            CacheTTL => $CacheTTL,

            # tickets with create time after ... (ticket newer than this date) (optional)
            TicketCloseTimeNewerDate => $TimeStart,

            # tickets with created time before ... (ticket older than this date) (optional)
            TicketCloseTimeOlderDate => $TimeStop,

            CustomerID => $Param{Data}->{UserCustomerID},
            Result     => 'COUNT',

            # search with user permissions
            Permission => $Self->{Config}->{Permission} || 'ro',
            UserID => $Self->{UserID},
        );
        if ( $CountClosed && $CountClosed > $Max ) {
            $Max = $CountClosed;
        }
        push @TicketsClosed, $CountClosed;
    }

=cut

    }

    unshift(
        @TicketWeekdays,
        $StateText
    );

    my @ChartData = (
# ---
# PS
# ---
#        $LayoutObject->{LanguageObject}->Translate('7 Day Stats'),
        $LayoutObject->{LanguageObject}->Translate(
            $ConfigObject->Get('GenericDashboardStats::Title')
        ),
# ---
        \@TicketWeekdays,
# ---
# PS
# ---
#        [ $CreatedText, reverse @TicketsCreated ],
#        [ $ClosedText,  reverse @TicketsClosed ],
        @ShownStats,
# ---
    );

    my $ChartDataJSON = $LayoutObject->JSONEncode(
        Data => \@ChartData,
    );

    my %Data = (
        %{ $Self->{Config} },
        Key       => int rand 99999,
        ChartData => $ChartDataJSON,
    );

    if ( $Self->{Config}->{CacheTTLLocal} ) {
        $Kernel::OM->Get('Kernel::System::Cache')->Set(
            Type  => 'Dashboard',
            Key   => $CacheKey,
            Value => \%Data,
            TTL   => $Self->{Config}->{CacheTTLLocal} * 60,
        );
    }

    my $Content = $LayoutObject->Output(
        TemplateFile   => 'AgentDashboardTicketStats',
        Data           => \%Data,
        KeepScriptTags => $Param{AJAX},
    );

    return $Content;
}

1;
