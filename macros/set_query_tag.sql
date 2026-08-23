{#
  Snowflake QUERY_TAG hook — tags every query dbt runs with the model name
  and invocation id, so you can filter QUERY_HISTORY by dbt run/model for
  cost and performance monitoring. Wired up in dbt_project.yml via
  on-run-start / pre-hook if desired; shown here as a reusable macro.
#}
{% macro set_query_tag() -%}
  {% set new_query_tag = "dbt|" ~ model.name ~ "|" ~ invocation_id %}
  {% if new_query_tag %}
    {% set original_query_tag = get_current_query_tag() %}
    {{ log("Setting query_tag to '" ~ new_query_tag ~ "'. Will reset to '" ~ original_query_tag ~ "' after model materializes.") }}
    alter session set query_tag = '{{ new_query_tag }}';
    {{ return(original_query_tag)}}
  {% endif %}
  {{ return(none)}}
{%- endmacro %}
