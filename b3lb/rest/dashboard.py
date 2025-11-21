from django.db.models import Sum, Count, Q
from rest.models import Cluster, Node, Tenant, Meeting, RecordSet
import json

def dashboard_callback(request, context):
    """
    Callback to prepare custom variables for index template which is used as dashboard
    template.
    """
    
    # --- KPI Stats ---
    total_clusters = Cluster.objects.count()
    total_nodes = Node.objects.count()
    active_nodes = Node.objects.filter(maintenance=False, has_errors=False).count()
    maintenance_nodes = Node.objects.filter(maintenance=True).count()
    error_nodes = Node.objects.filter(has_errors=True).count()
    total_tenants = Tenant.objects.count()
    
    meeting_stats = Meeting.objects.aggregate(
        total_meetings=Count('id'),
        total_attendees=Sum('attendees'),
        total_videos=Sum('videoCount'),
        total_voice=Sum('voiceParticipantCount')
    )
    total_meetings = meeting_stats['total_meetings'] or 0
    total_attendees = meeting_stats['total_attendees'] or 0
    
    recordings_processing = RecordSet.objects.filter(
        status__in=[RecordSet.UPLOADED, RecordSet.RENDERED]
    ).count()

    # --- Node Data ---
    nodes = Node.objects.select_related('cluster').all()
    nodes_data = []
    for node in nodes:
        status = "Online"
        status_color = "green"
        if node.maintenance:
            status = "Maintenance"
            status_color = "orange"
        elif node.has_errors:
            status = "Error"
            status_color = "red"
        
        nodes_data.append({
            "name": node.slug,
            "cluster": node.cluster.name,
            "status": status,
            "status_color": status_color,
            "attendees": node.attendees,
            "meetings": node.meetings,
            "cpu_load": node.cpu_load,
            "computed_load": node.load,
            "domain": node.domain
        })

    # --- Cluster Charts Data ---
    clusters = Cluster.objects.all()
    cluster_labels = [c.name for c in clusters]
    
    # Aggregate load per cluster (calculated in python since .load is a property)
    cluster_cpu_loads = []
    cluster_computed_loads = []
    
    for cluster in clusters:
        c_nodes = [n for n in nodes_data if n['cluster'] == cluster.name]
        cluster_cpu_loads.append(sum(n['cpu_load'] for n in c_nodes))
        cluster_computed_loads.append(sum(n['computed_load'] for n in c_nodes))

    cluster_chart_data = {
        "labels": cluster_labels,
        "datasets": [
            {
                "label": "CPU Load",
                "data": cluster_cpu_loads,
                "backgroundColor": "#9333ea", # Purple-600
                "borderColor": "#9333ea",
                "borderWidth": 1
            },
            {
                "label": "Computed Load",
                "data": cluster_computed_loads,
                "backgroundColor": "#2563eb", # Blue-600
                "borderColor": "#2563eb",
                "borderWidth": 1
            }
        ]
    }

    # --- Tenant Data ---
    # Top active tenants by attendees
    active_tenants = Tenant.objects.annotate(
        active_meetings=Count('secret__meeting', distinct=True),
        active_attendees=Sum('secret__meeting__attendees')
    ).filter(active_meetings__gt=0).order_by('-active_attendees')[:10]

    tenants_data = []
    for t in active_tenants:
        tenants_data.append({
            "name": t.slug,
            "meetings": t.active_meetings,
            "attendees": t.active_attendees or 0
        })

    # --- Context Update ---
    context.update({
        "kpi": [
            {
                "title": "Active Meetings",
                "metric": total_meetings,
                "footer": f"{total_attendees} Attendees | {meeting_stats['total_videos'] or 0} Videos",
                "icon": "monitor",
            },
            {
                "title": "Infrastructure",
                "metric": f"{active_nodes} / {total_nodes}",
                "footer": f"{total_clusters} Clusters | {error_nodes} Errors",
                "icon": "server",
            },
            {
                "title": "Tenants",
                "metric": total_tenants,
                "footer": f"{len(active_tenants)} Active Now",
                "icon": "people",
            },
             {
                "title": "Recordings Queue",
                "metric": recordings_processing,
                "footer": "Processing",
                "icon": "film",
            },
        ],
        "charts": {
            "cluster_load": cluster_chart_data
        },
        "tables": {
            "nodes": nodes_data,
            "tenants": tenants_data
        }
    })

    return context
