FROM klakegg/hugo:ext-ubuntu

EXPOSE 1313

COPY ./themes ./themes
COPY ./assets ./assets
COPY ./content ./content
COPY ./static ./static
COPY ./layouts ./layouts
COPY ./config.toml ./config.toml
CMD ["serve -D"]