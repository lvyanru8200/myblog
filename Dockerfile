FROM klakegg/hugo:ext-ubuntu

EXPOSE 1313

RUN hugo new site myblog && cd myblog \

WORKDIR myblog
COPY ./themes ./themes
COPY ./assets ./assets
COPY ./content ./content
COPY ./static ./static
COPY ./layouts ./layouts
COPY ./config.toml ./config.toml
CMD ["serve"]